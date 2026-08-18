// Same probe, but bounds how many sockets dart:io opens to the host at once.
// If the stall is triggered by opening N sockets simultaneously, queueing
// client-side should avoid it entirely.
import 'dart:convert';
import 'dart:io';

const _chunk =
    'def process(node, ctx):\n    # traverse the AST and rewrite bindings\n'
    '    for child in node.children:\n        ctx.visit(child, depth+1)\n'
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
  final rounds = int.parse(args[0]);
  final concurrency = int.parse(args[1]);
  final maxConns = int.parse(args[2]);
  final host = args[3];
  final prompt = _filler(32 * 1024);
  final uri = Uri.parse('$host/v1/chat/completions');
  final client = HttpClient()
    ..idleTimeout = const Duration(seconds: 3)
    ..maxConnectionsPerHost = maxConns;
  final sw = Stopwatch()..start();
  stdout.writeln('maxConnectionsPerHost=$maxConns concurrency=$concurrency');

  for (var round = 1; round <= rounds; round++) {
    final ok = <int, int>{};
    final start = sw.elapsedMilliseconds;
    Future<void> one(int i) async {
      final body = utf8.encode(
        json.encode({
          'model': 'Qwen/Qwen3.8-27B-FP8',
          'stream': true,
          'max_tokens': 128,
          'temperature': 0,
          'messages': [
            {
              'role': 'user',
              'content': '// mc r$round q$i\n$prompt\n\nName one bug.',
            },
          ],
        }),
      );
      final req = await client.postUrl(uri);
      req.headers.set('content-type', 'application/json');
      req.headers.set('accept', 'text/event-stream');
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 240));
      await res.drain<void>();
      ok[i] = sw.elapsedMilliseconds;
    }

    await Future.wait([
      for (var i = 0; i < concurrency; i++)
        one(i).catchError(
          (Object e) => stdout.writeln('  r$round q$i ERROR ${e.runtimeType}'),
        ),
    ]);
    final all = ok.values.map((v) => v - start).toList()..sort();
    stdout.writeln(
      'round $round: ${all.length}/$concurrency  '
      '${all.isEmpty ? '-' : '${all.first}..${all.last}ms'}',
    );
  }
  client.close();
}
