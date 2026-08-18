import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

/// These run against a real [HttpServer] rather than a mock client, because
/// the defects they guard against live *below* `package:http`'s abstraction:
/// how the body reaches the wire, and whether a send that never answers ever
/// unwinds. A mock client cannot observe either.
void main() {
  group('HttpClientHelper.sendStreamingRequest', () {
    late HttpServer server;
    late Uri uri;

    tearDown(() async => server.close(force: true));

    test('sends the whole body with a matching content-length', () async {
      List<int>? receivedBody;
      String? receivedContentLength;
      String? receivedTransferEncoding;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://127.0.0.1:${server.port}/');
      unawaited(
        server.first.then((request) async {
          receivedBody = await request.fold<List<int>>(
            <int>[],
            (acc, chunk) => acc..addAll(chunk),
          );
          receivedContentLength = request.headers.value('content-length');
          receivedTransferEncoding = request.headers.value('transfer-encoding');
          request.response
            ..statusCode = 200
            ..write('ok');
          await request.response.close();
        }),
      );

      // Large enough to exceed a single socket write, which is where a
      // half-flushed body would show up.
      final payload = utf8.encode(json.encode({'p': 'x' * 512 * 1024}));
      final helper = HttpClientHelper(httpClient: http.Client());

      final response = await helper.sendStreamingRequest(
        method: 'POST',
        uri: uri,
        headers: {'content-type': 'application/json'},
        body: payload,
      );
      await response.stream.drain<void>();

      expect(receivedBody, equals(payload));
      expect(receivedContentLength, equals(payload.length.toString()));
      // A declared content-length and chunked encoding are mutually exclusive;
      // setting the header by hand on a StreamedRequest used to negotiate both.
      expect(receivedTransferEncoding, isNot(equals('chunked')));
    });

    test('times out by default when the server never responds', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://127.0.0.1:${server.port}/');
      // Accept the request, read it, and then never answer — the shape of the
      // reported stall.
      unawaited(
        server.first.then((request) async {
          await request.drain<void>();
        }),
      );

      final helper = HttpClientHelper(
        httpClient: http.Client(),
        timeoutConfig: const TimeoutConfig(
          readTimeout: Duration(milliseconds: 300),
        ),
      );

      // No `applyTimeoutToSend` argument: the default must protect the caller.
      // It used to default to false, which returned an entirely untimed send.
      await expectLater(
        helper.sendStreamingRequest(
          method: 'POST',
          uri: uri,
          headers: {'content-type': 'application/json'},
          body: utf8.encode('{}'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('honours an explicit per-request timeout override', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://127.0.0.1:${server.port}/');
      unawaited(server.first.then((request) => request.drain<void>()));

      final helper = HttpClientHelper(
        httpClient: http.Client(),
        timeoutConfig: const TimeoutConfig(readTimeout: Duration(minutes: 5)),
      );

      final sw = Stopwatch()..start();
      await expectLater(
        helper.sendStreamingRequest(
          method: 'POST',
          uri: uri,
          headers: const {},
          body: utf8.encode('{}'),
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('opting out of the send timeout still reaches the server', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://127.0.0.1:${server.port}/');
      unawaited(
        server.first.then((request) async {
          await request.drain<void>();
          request.response.statusCode = 204;
          await request.response.close();
        }),
      );

      final helper = HttpClientHelper(httpClient: http.Client());
      final response = await helper.sendStreamingRequest(
        method: 'POST',
        uri: uri,
        headers: const {},
        body: utf8.encode('{}'),
        applyTimeoutToSend: false,
      );
      await response.stream.drain<void>();

      expect(response.statusCode, 204);
    });
  });

  group('createLLMHttpClient', () {
    test('produces a working client', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.first.then((request) async {
          await request.drain<void>();
          request.response.statusCode = 200;
          await request.response.close();
        }),
      );

      final client = createLLMHttpClient();
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      expect(response.statusCode, 200);
    });
  });
}
