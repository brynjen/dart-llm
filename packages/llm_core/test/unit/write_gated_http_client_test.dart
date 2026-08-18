import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

/// Guards the write-gate workaround for the macOS/iOS VM socket defect
/// documented in `docs/concurrent-send-stall.md`.
///
/// These drive a real [HttpServer] (and a raw, never-reading [ServerSocket]
/// for the stall cases) because the properties under test live below
/// `package:http`'s abstraction: *when* a slot is released relative to the
/// bytes reaching the kernel, and what happens when they never do.
void main() {
  group('WriteGatedHttpClient', () {
    test('releases the slot on body flush, not on response', () async {
      // A server that drains request bodies immediately but answers slowly.
      // With 6 requests through a gate of 2, all 6 bodies must arrive long
      // before the first response is produced — releasing on *response*
      // would let at most 2 bodies through per response delay.
      final bodyArrived = <int>[];
      final sw = Stopwatch()..start();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final responseGate = Completer<void>();
      unawaited(
        server
            .listen((request) async {
              await request.drain<void>();
              bodyArrived.add(sw.elapsedMilliseconds);
              await responseGate.future;
              request.response
                ..statusCode = 200
                ..write('ok');
              await request.response.close();
            })
            .asFuture<void>()
            .catchError((Object _) {}),
      );

      final client = WriteGatedHttpClient(HttpClient(), maxConcurrentWrites: 2);
      addTearDown(client.close);
      addTearDown(() => server.close(force: true));

      final requests = Future.wait([
        for (var i = 0; i < 6; i++)
          client.post(
            Uri.parse('http://127.0.0.1:${server.port}/$i'),
            body: 'x' * 1024,
          ),
      ]);

      // All six bodies arrive while every response is still held back.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        bodyArrived,
        hasLength(6),
        reason:
            'only ${bodyArrived.length} bodies arrived while responses were '
            'held — the gate is releasing on response, not on flush',
      );

      responseGate.complete();
      final responses = await requests;
      expect(responses.map((r) => r.statusCode), everyElement(200));
    });

    test(
      'a stalled write holds its slot and queues the next request',
      () async {
        // Request A writes 32MB at a peer that never reads, so its flush()
        // cannot complete; with a gate of 1, request B must not start until
        // A's write watchdog aborts it.
        final blackhole = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final held = <Socket>[];
        blackhole.listen(held.add); // accept, never read

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sw = Stopwatch()..start();
        int? bArrivedMs;
        unawaited(
          server
              .listen((request) async {
                bArrivedMs = sw.elapsedMilliseconds;
                await request.drain<void>();
                request.response.statusCode = 200;
                await request.response.close();
              })
              .asFuture<void>()
              .catchError((Object _) {}),
        );

        final client = WriteGatedHttpClient(
          HttpClient(),
          maxConcurrentWrites: 1,
          writeTimeout: const Duration(milliseconds: 500),
        );
        addTearDown(client.close);
        addTearDown(() async {
          for (final s in held) {
            s.destroy();
          }
          await blackhole.close();
          await server.close(force: true);
        });

        // Chunked (unknown content-length) so the write deadline is the flat
        // [writeTimeout] rather than being scaled up for the huge body.
        final stallRequest = http.StreamedRequest(
          'POST',
          Uri.parse('http://127.0.0.1:${blackhole.port}/stall'),
        );
        for (var i = 0; i < 32; i++) {
          stallRequest.sink.add(Uint8List(1024 * 1024));
        }
        unawaited(stallRequest.sink.close());
        final a = client
            .send(stallRequest)
            .then<Object?>((r) => r, onError: (Object e) => e);
        // Give A time to acquire the slot and start writing.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final b = client.get(
          Uri.parse('http://127.0.0.1:${server.port}/after'),
        );

        final aOutcome = await a;
        expect(
          aOutcome,
          isA<TimeoutException>(),
          reason: 'the write watchdog must abort a stalled write',
        );

        final bResponse = await b;
        expect(bResponse.statusCode, 200);
        expect(
          bArrivedMs,
          greaterThanOrEqualTo(400),
          reason:
              'B reached the server after ${bArrivedMs}ms — it must queue '
              'behind A until the watchdog frees the slot at ~500ms',
        );
      },
    );

    test('plain requests round-trip with body and headers intact', () async {
      List<int>? received;
      String? contentLength;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.first.then((request) async {
          received = await request.fold<List<int>>(
            <int>[],
            (acc, chunk) => acc..addAll(chunk),
          );
          contentLength = request.headers.value('content-length');
          request.response
            ..statusCode = 201
            ..headers.set('x-echo', 'yes')
            ..write('done');
          await request.response.close();
        }),
      );

      final client = WriteGatedHttpClient(HttpClient());
      addTearDown(client.close);
      addTearDown(() => server.close(force: true));

      final payload = List<int>.generate(300 * 1024, (i) => i % 251);
      final response = await client.post(
        Uri.parse('http://127.0.0.1:${server.port}/echo'),
        body: payload,
      );

      expect(response.statusCode, 201);
      expect(response.body, 'done');
      expect(response.headers['x-echo'], 'yes');
      expect(received, equals(payload));
      expect(contentLength, payload.length.toString());
    });

    test('connection failures surface as ClientException+SocketException', () {
      final client = WriteGatedHttpClient(
        HttpClient()..connectionTimeout = const Duration(seconds: 2),
      );
      addTearDown(client.close);
      // A port from the discard range that nothing listens on.
      expect(
        client.get(Uri.parse('http://127.0.0.1:9/')),
        throwsA(allOf(isA<http.ClientException>(), isA<SocketException>())),
      );
    });
  });

  group('createLLMHttpClient maxConcurrentWrites', () {
    test('explicit bound gates on every platform', () {
      final client = createLLMHttpClient(maxConcurrentWrites: 3);
      expect(client, isA<WriteGatedHttpClient>());
      expect((client as WriteGatedHttpClient).maxConcurrentWrites, 3);
      client.close();
    });

    test('explicit zero disables the gate on every platform', () {
      final client = createLLMHttpClient(maxConcurrentWrites: 0);
      expect(client, isA<IOClient>());
      client.close();
    });

    test('platform default gates only on kqueue platforms', () {
      final client = createLLMHttpClient();
      if (Platform.isMacOS || Platform.isIOS) {
        expect(client, isA<WriteGatedHttpClient>());
        expect(
          (client as WriteGatedHttpClient).maxConcurrentWrites,
          kLLMMaxConcurrentWrites,
        );
      } else {
        expect(client, isA<IOClient>());
      }
      client.close();
    });
  });
}
