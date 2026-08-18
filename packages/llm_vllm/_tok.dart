// 16 concurrent /tokenize calls from ONE isolate, raw dart:io. No engine work,
// so a stall here is purely HTTP-layer.
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
  final maxConns = int.parse(args[2]); // 0 = unbounded
  final host = args[3];
  final prompt = _filler(32 * 1024);
  final uri = Uri.parse('$host/tokenize');
  final client = HttpClient()..idleTimeout = const Duration(seconds: 3);
  if (maxConns > 0) client.maxConnectionsPerHost = maxConns;
  final sw = Stopwatch()..start();
  var slow = 0, failed = 0, total = 0;
  stdout.writeln(
    'tokenize probe: concurrency=$concurrency '
    'maxConns=${maxConns == 0 ? "unbounded" : maxConns} rounds=$rounds',
  );

  for (var round = 1; round <= rounds; round++) {
    final lat = <int>[];
    Future<void> one(int i) async {
      final t = sw.elapsedMilliseconds;
      final body = utf8.encode(
        json.encode({
          'model': 'Qwen/Qwen3.8-27B-FP8',
          'prompt': '// r$round q$i\n$prompt',
        }),
      );
      final req = await client.postUrl(uri);
      req.headers.set('content-type', 'application/json');
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 30));
      await res.drain<void>();
      lat.add(sw.elapsedMilliseconds - t);
    }

    await Future.wait([
      for (var i = 0; i < concurrency; i++)
        one(i).catchError((Object e) {
          failed++;
          stdout.writeln('  r$round q$i ERROR ${e.runtimeType}');
        }),
    ]);
    total += concurrency;
    lat.sort();
    if (lat.isNotEmpty && lat.last > 3000) {
      slow++;
      stdout.writeln(
        'round $round SLOW: ${lat.length}/$concurrency '
        'min=${lat.first}ms max=${lat.last}ms',
      );
    }
  }
  stdout.writeln(
    'done: $total requests, $failed failed, '
    '$slow/$rounds rounds with a >3s outlier',
  );
  client.close();
}
