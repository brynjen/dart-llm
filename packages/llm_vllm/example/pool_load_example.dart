/// Load-tests a vLLM server through [VLLMPool] to see what it sustains at
/// full batch.
///
/// Runs a short single-stream baseline, then fires the full batch with all
/// requests in flight at once. Throughput is computed from the actual
/// completion tokens reported in `usage`, so early stops don't skew the
/// numbers. (`ignore_eos: true` would make request sizes exact, but it
/// correlated with an EngineCore SIGSEGV on at least one server build, so it
/// is deliberately not sent.)
///
/// ```bash
/// VLLM_BASE_URL=http://192.168.0.74:8000 \
/// VLLM_CHAT_MODEL=nvidia/Qwen3.6-27B-NVFP4 \
/// dart run example/pool_load_example.dart [concurrency] [requests] [tokens]
/// ```
///
/// Defaults: 32 concurrent, 64 requests, 256 tokens each.
library;

import 'dart:io';
import 'dart:math';

import 'package:llm_vllm/llm_vllm.dart';

Future<void> main(List<String> args) async {
  final baseUrl =
      Platform.environment['VLLM_BASE_URL'] ?? 'http://localhost:8000';
  final model = Platform.environment['VLLM_CHAT_MODEL'] ?? 'Qwen/Qwen3-0.6B';
  final concurrency = args.isNotEmpty ? int.parse(args[0]) : 32;
  final totalRequests = args.length > 1 ? int.parse(args[1]) : 64;
  final maxTokens = args.length > 2 ? int.parse(args[2]) : 256;

  stdout.writeln('server:      $baseUrl');
  stdout.writeln('model:       $model');
  stdout.writeln(
    'plan:        $totalRequests requests x $maxTokens tokens, '
    '$concurrency in flight\n',
  );

  final pool = VLLMPool(
    instances: [
      VLLMInstanceConfig(baseUrl: baseUrl, maxConcurrent: concurrency),
    ],
  );

  try {
    stdout.writeln('--- baseline: 1 request at a time (2 requests) ---');
    final baseline = await _runBatch(
      pool,
      model,
      requests: 2,
      maxTokens: maxTokens,
      sequential: true,
    );
    _report(baseline);

    stdout.writeln('\n--- full batch: $concurrency in flight ---');
    final batch = await _runBatch(
      pool,
      model,
      requests: totalRequests,
      maxTokens: maxTokens,
    );
    _report(batch);

    final speedup =
        batch.aggregateTokensPerSecond / baseline.aggregateTokensPerSecond;
    stdout.writeln(
      '\nbatching gain: ${speedup.toStringAsFixed(1)}x aggregate throughput '
      'over single-stream',
    );
  } finally {
    pool.dispose();
  }
}

class _BatchResult {
  _BatchResult(this.wall, this.results);

  final Duration wall;
  final List<_RequestResult> results;

  int get totalTokens => results.fold(0, (sum, r) => sum + r.completionTokens);

  double get aggregateTokensPerSecond =>
      totalTokens / (wall.inMilliseconds / 1000);
}

class _RequestResult {
  _RequestResult(this.duration, this.firstToken, this.completionTokens);

  final Duration duration;
  final Duration? firstToken;
  final int completionTokens;
}

Future<_BatchResult> _runBatch(
  VLLMPool pool,
  String model, {
  required int requests,
  required int maxTokens,
  bool sequential = false,
}) async {
  var completed = 0;
  final wall = Stopwatch()..start();

  Future<_RequestResult> tracked(int i) =>
      _oneRequest(pool, model, i, maxTokens).then((r) {
        completed++;
        if (completed % 10 == 0 || completed == requests) {
          stdout.writeln(
            '  $completed/$requests done at '
            '${(wall.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
          );
        }
        return r;
      });

  final List<_RequestResult> results;
  if (sequential) {
    // A true single-stream measurement: each request finishes before the
    // next starts, regardless of the pool's concurrency limit.
    results = [for (var i = 0; i < requests; i++) await tracked(i)];
  } else {
    results = await Future.wait([
      for (var i = 0; i < requests; i++) tracked(i),
    ]);
  }
  wall.stop();
  return _BatchResult(wall.elapsed, results);
}

Future<_RequestResult> _oneRequest(
  VLLMPool pool,
  String model,
  int index,
  int maxTokens,
) async {
  final sw = Stopwatch()..start();
  Duration? firstToken;
  var completionTokens = 0;

  // Varied prompts so prefix caching cannot trivialize prefill.
  final stream = pool.streamChat(
    model,
    messages: [
      LLMMessage(
        role: LLMRole.user,
        content:
            'This is load-test request #$index. Write a rambling story '
            'about the number ${index * 7 % 100} and a ${_nouns[index % _nouns.length]}.',
      ),
    ],
    options: LLMChatOptions(think: false, maxOutputTokens: maxTokens),
  );

  await for (final chunk in stream) {
    if (firstToken == null && (chunk.message?.content?.isNotEmpty ?? false)) {
      firstToken = sw.elapsed;
    }
    if (chunk.usage != null) {
      completionTokens = chunk.usage!.completionTokens;
    }
  }
  sw.stop();
  return _RequestResult(sw.elapsed, firstToken, completionTokens);
}

void _report(_BatchResult batch) {
  final durations = batch.results.map((r) => r.duration).toList()
    ..sort((a, b) => a.compareTo(b));
  final ttfts =
      batch.results.map((r) => r.firstToken).whereType<Duration>().toList()
        ..sort((a, b) => a.compareTo(b));

  String seconds(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';
  Duration percentile(List<Duration> sorted, double p) =>
      sorted[min((sorted.length * p).floor(), sorted.length - 1)];

  stdout.writeln('  wall time:            ${seconds(batch.wall)}');
  stdout.writeln('  completion tokens:    ${batch.totalTokens}');
  stdout.writeln(
    '  aggregate throughput: '
    '${batch.aggregateTokensPerSecond.toStringAsFixed(1)} tok/s',
  );
  stdout.writeln(
    '  request latency:      p50 ${seconds(percentile(durations, 0.5))}, '
    'p95 ${seconds(percentile(durations, 0.95))}',
  );
  if (ttfts.isNotEmpty) {
    stdout.writeln(
      '  time to first token:  p50 ${seconds(percentile(ttfts, 0.5))}, '
      'p95 ${seconds(percentile(ttfts, 0.95))}',
    );
  }
}

const _nouns = [
  'lighthouse',
  'tram',
  'glacier',
  'chessboard',
  'accordion',
  'submarine',
  'orchard',
  'typewriter',
];
