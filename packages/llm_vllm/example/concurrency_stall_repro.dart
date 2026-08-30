/// Minimal reproduction for the concurrent-`send()` stall.
///
/// See `docs/concurrent-send-stall.md` at the repository root.
///
/// Fires batches of concurrent `chatResponse` calls through a **single shared**
/// [VLLMChatRepository] — the shared client is required to trigger the bug; one
/// process per request (e.g. `curl`) never reproduces it.
///
/// The stall is *self-healing*: the send timeout eventually fires and the retry
/// succeeds immediately, so counting errors finds nothing. The signal that does
/// work is **latency dispersion** — a wedged request takes a full `readTimeout`
/// while its siblings take seconds. This harness therefore fails a batch when
/// any request exceeds `--stall-factor` × the batch median.
///
/// Usage:
///   dart run example/concurrency_stall_repro.dart \
///     --host "$VLLM_BASE_URL" \
///     --model Qwen/Qwen3.8-27B-FP8 \
///     --concurrency 16 --prompt-ktokens 32 --batches 20 \
///     --read-timeout-seconds 60
///
/// `--client` selects how the underlying connection pool behaves, which is how
/// the "reused pooled connection" hypothesis gets tested without touching
/// library code:
///
///   shipped     no client passed — the repository's own `createLLMHttpClient()`
///   default     one shared plain `http.Client()`
///   no-reuse    forces `Connection: close`, so every request gets a fresh socket
///   short-idle  bounded pool whose idle timeout expires before the server's
///
/// Set `LLM_VLLM_TRACE=1` to see which await never returns; a wedged request
/// prints `send.begin` with no following `send.headers`.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:llm_vllm/llm_vllm.dart';

const _chunk =
    'def process(node, ctx):\n'
    '    # traverse the AST and rewrite bindings\n'
    '    for child in node.children:\n'
    '        ctx.visit(child, depth+1)\n'
    '    return ctx.resolve(node.symbol, scope=node.scope, strict=True)\n\n';

/// ~4 chars per token for this code-shaped text.
String _filler(int tokens) {
  final target = tokens * 4;
  final sb = StringBuffer();
  while (sb.length < target) {
    sb.write(_chunk);
  }
  return sb.toString().substring(0, target);
}

/// Forces a fresh TCP connection per request by asking for `Connection: close`.
///
/// If the stall disappears under this client, the defect is in connection
/// *reuse*, not in how the request itself is built.
class _NoReuseClient extends http.BaseClient {
  _NoReuseClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.persistentConnection = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

http.Client? _buildClient(String variant) {
  switch (variant) {
    case 'shipped':
      // null => the repository builds its own via createLLMHttpClient(), which
      // is what a caller who passes no client actually gets.
      return null;
    case 'default':
      return http.Client();
    case 'no-reuse':
      return _NoReuseClient(http.Client());
    case 'short-idle':
      // uvicorn's default keep-alive is 5s while dart:io's idleTimeout is 15s,
      // which leaves a ~10s window where the client will happily reuse a
      // connection the server has already reaped.
      return IOClient(
        HttpClient()
          ..idleTimeout = const Duration(seconds: 2)
          ..connectionTimeout = const Duration(seconds: 10)
          ..maxConnectionsPerHost = 64,
      );
    default:
      stderr.writeln(
        'unknown --client "$variant" (shipped|default|no-reuse|short-idle)',
      );
      exit(2);
  }
}

/// Latency percentile from an already-sorted list of milliseconds.
int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

Future<void> main(List<String> args) async {
  final host = _arg(args, '--host') ?? 'http://localhost:8000';
  final model = _arg(args, '--model') ?? 'Qwen/Qwen3.8-27B-FP8';
  final concurrency = int.parse(_arg(args, '--concurrency') ?? '16');
  final promptKTokens = int.parse(_arg(args, '--prompt-ktokens') ?? '32');
  final batches = int.parse(_arg(args, '--batches') ?? '20');
  final maxTokens = int.parse(_arg(args, '--max-tokens') ?? '128');
  final clientVariant = _arg(args, '--client') ?? 'default';
  final readTimeout = Duration(
    seconds: int.parse(_arg(args, '--read-timeout-seconds') ?? '900'),
  );
  // A request is "stalled" when it takes this many times the batch median. The
  // absolute floor keeps a fast batch with normal jitter from tripping it.
  final stallFactor = double.parse(_arg(args, '--stall-factor') ?? '5');
  final stallFloor = Duration(
    seconds: int.parse(_arg(args, '--stall-floor-seconds') ?? '30'),
  );
  // A batch that legitimately takes minutes must not be called a stall; this is
  // only the "obviously wedged, stop waiting" line.
  final watchdog = Duration(
    seconds: int.parse(_arg(args, '--watchdog-seconds') ?? '1800'),
  );

  stdout.writeln(
    'repro: host=$host model=$model concurrency=$concurrency '
    'prompt=${promptKTokens}k batches=$batches client=$clientVariant\n'
    'readTimeout=${readTimeout.inSeconds}s watchdog=${watchdog.inSeconds}s '
    'stall=>${stallFactor}x median (floor ${stallFloor.inSeconds}s)\n',
  );

  final prompt = _filler(promptKTokens * 1024);

  // ONE repository, therefore one pooled client, for the whole run.
  final repo = VLLMChatRepository(
    baseUrl: host,
    httpClient: _buildClient(clientVariant),
    timeoutConfig: TimeoutConfig(readTimeout: readTimeout),
  );

  var sent = 0;
  var completed = 0;
  var errored = 0;
  final allLatencies = <int>[];
  final batchWalls = <int>[];

  try {
    for (var batch = 1; batch <= batches; batch++) {
      final done = <int>{};
      final latencies = <int, int>{};
      final sw = Stopwatch()..start();

      Future<void> one(int i) async {
        sent++;
        final rsw = Stopwatch()..start();
        try {
          await repo.chatResponse(
            model,
            messages: [
              LLMMessage(
                role: LLMRole.user,
                // Unique per request: defeats prefix-cache reuse so every
                // request does real work.
                content: '// batch $batch request $i\n$prompt\n\nName one bug.',
              ),
            ],
            options: LLMChatOptions(maxOutputTokens: maxTokens, temperature: 0),
          );
          completed++;
          done.add(i);
        } catch (e) {
          errored++;
          completed++;
          done.add(i);
          stdout.writeln(
            '  batch $batch req $i errored: '
            '${e.runtimeType} — ${e.toString().split('\n').first}',
          );
        } finally {
          latencies[i] = rsw.elapsedMilliseconds;
        }
      }

      final work = Future.wait([for (var i = 0; i < concurrency; i++) one(i)]);

      try {
        await work.timeout(watchdog);
      } on TimeoutException {
        final stuck = [
          for (var i = 0; i < concurrency; i++)
            if (!done.contains(i)) i,
        ];
        stdout.writeln(
          '\n*** WEDGED past the watchdog on batch $batch after '
          '${sw.elapsed.inSeconds}s ***\n'
          'sent=$sent completed=$completed\n'
          'requests still pending: $stuck (${stuck.length} of $concurrency)\n\n'
          'Confirm the signature now, while it is wedged:\n'
          "  netstat -an | grep '${Uri.parse(host).host}.${Uri.parse(host).port}' "
          "| awk '{print \$NF}' | sort | uniq -c\n"
          '  curl -s $host/metrics | grep -E '
          "'^vllm:(num_requests_running|num_requests_waiting|request_success_total)'",
        );
        exit(1);
      }

      final sorted = latencies.values.toList()..sort();
      allLatencies.addAll(latencies.values);
      batchWalls.add(sw.elapsedMilliseconds);

      stdout.writeln(
        'batch $batch/$batches wall=${sw.elapsed.inSeconds}s '
        'p50=${(_percentile(sorted, 0.5) / 1000).toStringAsFixed(1)}s '
        'p90=${(_percentile(sorted, 0.9) / 1000).toStringAsFixed(1)}s '
        'max=${(sorted.last / 1000).toStringAsFixed(1)}s '
        '(sent=$sent err=$errored)',
      );
    }
  } finally {
    repo.close();
  }

  // Judged against the *run* median, not the batch median. A stall that wedges
  // a whole batch inflates that batch's own median along with it, so a
  // per-batch comparison scores the worst batches as normal — which is how a
  // 74s batch among 11s batches was first missed.
  final sortedAll = allLatencies.toList()..sort();
  final median = _percentile(sortedAll, 0.5);
  final threshold = [
    (median * stallFactor).round(),
    stallFloor.inMilliseconds,
  ].reduce((a, b) => a > b ? a : b);
  final stalled = allLatencies.where((ms) => ms > threshold).toList()..sort();

  final sortedWalls = batchWalls.toList()..sort();
  final wallMedian = _percentile(sortedWalls, 0.5);
  final slowBatches = batchWalls
      .asMap()
      .entries
      .where((e) => e.value > wallMedian * stallFactor)
      .map((e) => '#${e.key + 1}=${(e.value / 1000).toStringAsFixed(0)}s')
      .toList();

  stdout.writeln(
    '\nsummary client=$clientVariant sent=$sent completed=$completed '
    'errors=$errored\n'
    'run median=${(median / 1000).toStringAsFixed(1)}s '
    'p90=${(_percentile(sortedAll, 0.9) / 1000).toStringAsFixed(1)}s '
    'p99=${(_percentile(sortedAll, 0.99) / 1000).toStringAsFixed(1)}s '
    'max=${(sortedAll.last / 1000).toStringAsFixed(1)}s\n'
    'stall threshold=${(threshold / 1000).toStringAsFixed(1)}s '
    '(${stallFactor}x median, floor ${stallFloor.inSeconds}s)',
  );
  if (slowBatches.isNotEmpty) {
    stdout.writeln(
      'batches over ${stallFactor}x the median batch wall '
      '(${(wallMedian / 1000).toStringAsFixed(0)}s): '
      '${slowBatches.join(', ')}',
    );
  }
  if (stalled.isNotEmpty) {
    stdout.writeln(
      'FAIL: ${stalled.length} of $sent request(s) stalled — '
      '${stalled.map((ms) => '${(ms / 1000).toStringAsFixed(0)}s').join(', ')}',
    );
    exit(1);
  }
  stdout.writeln('PASS: no stalls in $sent requests');
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}
