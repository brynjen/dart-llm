/// Minimal reproducer for the `send()` stall, with no `package:http` involved.
///
/// See `docs/concurrent-send-stall.md`. This exists to answer one question:
/// is the stall ours, or `dart:io`'s? It issues the same shape of traffic as
/// `concurrency_stall_repro.dart` — N concurrent large POSTs to one host from
/// a single isolate — against `dart:io`'s `HttpClient` directly.
///
/// Observed on Dart 3.12.2 (macOS client, Ubuntu vLLM server over LAN), from a
/// verified-idle server, on the **first** round:
///
/// ```
///   r1 q5 ERROR TimeoutException     (and q7, q8, q9, q11)
///   round 1: headers 126..369ms (11/16)  total 60065..60833ms (11/16)
/// ```
///
/// Eleven of sixteen requests get response headers within 369ms. The other
/// five never get headers at all and die on the timeout. Meanwhile 48
/// equivalent `curl` requests (one process each, three rounds of sixteen) all
/// reach first byte in 0.07–0.45s, 48/48 HTTP 200 — so the server is answering
/// everything it is asked. `netstat` shows `Send-Q = 0` on the wedged sockets,
/// so the client is not blocked writing either.
///
/// Usage:
///   dart run example/dart_io_stall_probe.dart \
///     [rounds] [concurrency] [prompt-ktokens] [host] [model]
///
/// Drain the server to idle before running — vLLM keeps executing requests
/// from a killed client, and a run queued behind that backlog looks wedged for
/// entirely uninteresting reasons:
///   curl -s http://HOST/metrics | grep -E 'num_requests_(running|waiting)\{'
library;

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
  final rounds = int.parse(args.isNotEmpty ? args[0] : '6');
  final concurrency = int.parse(args.length > 1 ? args[1] : '16');
  final promptKTokens = int.parse(args.length > 2 ? args[2] : '32');
  final host = args.length > 3 ? args[3] : 'http://localhost:8000';
  final model = args.length > 4 ? args[4] : 'Qwen/Qwen3.8-27B-FP8';

  final prompt = _filler(promptKTokens * 1024);
  final uri = Uri.parse('$host/v1/chat/completions');
  final client = HttpClient()..idleTimeout = const Duration(seconds: 3);
  final sw = Stopwatch()..start();

  stdout.writeln(
    'raw dart:io probe: $host $model concurrency=$concurrency '
    'prompt=${promptKTokens}k rounds=$rounds\n',
  );

  for (var round = 1; round <= rounds; round++) {
    final headerMs = <int, int>{};
    final doneMs = <int, int>{};
    final start = sw.elapsedMilliseconds;

    Future<void> one(int i) async {
      final body = utf8.encode(
        json.encode({
          'model': model,
          'stream': true,
          'max_tokens': 128,
          'temperature': 0,
          'messages': [
            {
              'role': 'user',
              // Unique per request so prefix caching cannot serve it.
              'content': '// raw r$round q$i\n$prompt\n\nName one bug.',
            },
          ],
        }),
      );
      final request = await client.postUrl(uri);
      request.headers.set('content-type', 'application/json');
      request.headers.set('accept', 'text/event-stream');
      request.contentLength = body.length;
      request.add(body);
      // Without the timeout a wedged request hangs the round forever.
      final response = await request.close().timeout(
        const Duration(seconds: 240),
      );
      headerMs[i] = sw.elapsedMilliseconds;
      await response.drain<void>();
      doneMs[i] = sw.elapsedMilliseconds;
    }

    await Future.wait([
      for (var i = 0; i < concurrency; i++)
        one(i).catchError((Object e) {
          stdout.writeln('  r$round q$i ERROR ${e.runtimeType}');
        }),
    ]);

    final hdr = headerMs.values.map((v) => v - start).toList()..sort();
    final all = doneMs.values.map((v) => v - start).toList()..sort();
    stdout.writeln(
      'round $round: headers '
      '${hdr.isEmpty ? '-' : '${hdr.first}..${hdr.last}ms'} '
      '(${hdr.length}/$concurrency)  total '
      '${all.isEmpty ? '-' : '${all.first}..${all.last}ms'} '
      '(${all.length}/$concurrency)',
    );
  }
  // force: a wedged request holds its socket forever, and a plain close()
  // waits for it — the probe process would never exit.
  client.close(force: true);
}
