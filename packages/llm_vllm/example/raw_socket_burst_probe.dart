/// Raw dart:io Socket probe for the burst write-stall — no HttpClient at all.
///
/// Opens N sockets to the vLLM server simultaneously, writes a complete HTTP
/// POST (headers + ~132KB JSON body) on each, and reports three timestamps per
/// socket:
///   connect  – Socket.connect completed
///   flushed  – Socket.flush() completed (bytes accepted by the local kernel)
///   firstByte – first response byte arrived
///
/// If some sockets never reach `flushed`, the stall is in the VM's socket
/// write path / event handler. If all flush but some get no response, the
/// stall is server-side (already disproven). If none stall, the bug lives in
/// HttpClient's plumbing above raw sockets.
///
/// Usage:
///   dart raw_socket_burst_probe.dart \
///     [rounds] [concurrency] [ktokens] [host] [port] [model] [stagger-ms] [gate]
///
/// `stagger-ms` > 0 delays each connect by `i * stagger-ms` (the time-based
/// workaround); `gate` > 0 bounds concurrent connect+write phases with a
/// semaphore released on flush (the queue-based workaround `llm_core` ships
/// as `WriteGatedHttpClient`). With both 0, the VM defect wedges some
/// sockets; with either engaged, every socket flushes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _chunk =
    'def process(node, ctx):\n'
    '    # traverse the AST and rewrite bindings\n'
    '    for child in node.children:\n'
    '        ctx.visit(child, depth+1)\n'
    '    return ctx.resolve(node.symbol, scope=node.scope, strict=True)\n\n';

String _filler(int tokens) {
  final target = tokens * 4;
  final sb = StringBuffer();
  while (sb.length < target) {
    sb.write(_chunk);
  }
  return sb.toString().substring(0, target);
}

Future<void> main(List<String> args) async {
  final rounds = int.parse(args.isNotEmpty ? args[0] : '3');
  final concurrency = int.parse(args.length > 1 ? args[1] : '16');
  final ktokens = int.parse(args.length > 2 ? args[2] : '32');
  final host = args.length > 3 ? args[3] : 'localhost';
  final port = int.parse(args.length > 4 ? args[4] : '8000');
  final model = args.length > 5 ? args[5] : 'Qwen/Qwen3.8-27B-FP8';
  final staggerMs = int.parse(args.length > 6 ? args[6] : '0');
  // >0: bound concurrent connect+write phases with a semaphore released when
  // flush() completes — the queue-based alternative to time-based staggering.
  final gate = int.parse(args.length > 7 ? args[7] : '0');

  final prompt = _filler(ktokens * 1024);
  final sw = Stopwatch()..start();

  stdout.writeln(
    'raw socket probe: $host:$port concurrency=$concurrency '
    'prompt=${ktokens}k rounds=$rounds stagger=${staggerMs}ms gate=$gate',
  );

  // Minimal counting semaphore for the gate mode.
  var gateActive = 0;
  final gateWaiters = <Completer<void>>[];
  Future<void> gateAcquire() {
    if (gate <= 0 || gateActive < gate) {
      gateActive++;
      return Future.value();
    }
    final c = Completer<void>();
    gateWaiters.add(c);
    return c.future.then((_) => gateActive++);
  }

  void gateRelease() {
    if (gate <= 0) return;
    gateActive--;
    if (gateWaiters.isNotEmpty) {
      gateWaiters.removeAt(0).complete();
    }
  }

  for (var round = 1; round <= rounds; round++) {
    final connectMs = <int, int>{};
    final flushedMs = <int, int>{};
    final firstByteMs = <int, int>{};
    final sockets = <Socket>[];
    final start = sw.elapsedMilliseconds;

    Future<void> one(int i) async {
      final body = utf8.encode(
        json.encode({
          'model': model,
          'stream': false,
          'max_tokens': 8,
          'temperature': 0,
          'messages': [
            {
              'role': 'user',
              'content': '// raw-socket r$round q$i\n$prompt\n\nName one bug.',
            },
          ],
        }),
      );
      final header = ascii.encode(
        'POST /v1/chat/completions HTTP/1.1\r\n'
        'host: $host:$port\r\n'
        'content-type: application/json\r\n'
        'accept: application/json\r\n'
        'connection: close\r\n'
        'content-length: ${body.length}\r\n'
        '\r\n',
      );
      if (staggerMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: staggerMs * i));
      }
      await gateAcquire();
      final socket = await Socket.connect(host, port);
      sockets.add(socket);
      connectMs[i] = sw.elapsedMilliseconds - start;
      final firstByte = Completer<void>();
      // Swallow errors up front — this future is observational only, and a
      // completer error at socket teardown must not crash the probe.
      unawaited(firstByte.future.catchError((Object _) {}));
      socket.listen(
        (data) {
          if (!firstByte.isCompleted) {
            firstByteMs[i] = sw.elapsedMilliseconds - start;
            firstByte.complete();
          }
        },
        onError: (Object _) {
          if (!firstByte.isCompleted) firstByte.completeError('socket error');
        },
        onDone: () {
          if (!firstByte.isCompleted) firstByte.completeError('closed');
        },
      );
      socket.add(header);
      socket.add(body);
      await socket.flush();
      flushedMs[i] = sw.elapsedMilliseconds - start;
      gateRelease();
      // First byte is not awaited: the decisive measurement is flush().
      // Server-side behavior is already established; sockets are destroyed
      // after the round so the server aborts the work early.
    }

    await Future.wait([
      for (var i = 0; i < concurrency; i++)
        one(i).timeout(const Duration(seconds: 45)).catchError((Object e) {
          stdout.writeln('  r$round q$i ERROR ${e.runtimeType}');
        }),
    ]);

    String fmt(Map<int, int> m) {
      if (m.isEmpty) return '-';
      final v = m.values.toList()..sort();
      return '${v.first}..${v.last}ms (${v.length}/$concurrency)';
    }

    stdout.writeln(
      'round $round: connect ${fmt(connectMs)}  flushed ${fmt(flushedMs)}  '
      'firstByte ${fmt(firstByteMs)}',
    );
    final stuckInWrite = [
      for (var i = 0; i < concurrency; i++)
        if (connectMs.containsKey(i) && !flushedMs.containsKey(i)) i,
    ];
    final stuckWaiting = [
      for (var i = 0; i < concurrency; i++)
        if (flushedMs.containsKey(i) && !firstByteMs.containsKey(i)) i,
    ];
    if (stuckInWrite.isNotEmpty) {
      stdout.writeln('  NEVER FLUSHED (write path stall): $stuckInWrite');
    }
    if (stuckWaiting.isNotEmpty) {
      stdout.writeln('  flushed but no response: $stuckWaiting');
    }
    for (final s in sockets) {
      s.destroy();
    }
    // Let the server abort the closed requests before the next round.
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  exit(0);
}
