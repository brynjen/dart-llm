/// Interface for collecting metrics about LLM operations.
///
/// Implementations can track request counts, latencies, token usage, and errors.
///
/// Example:
/// ```dart
/// class MyMetrics implements LLMMetrics {
///   @override
///   void recordRequest({required String model, required bool success}) {
///     // Track request
///   }
///   // ... implement other methods
/// }
/// ```
abstract class LLMMetrics {
  /// Record a request attempt.
  ///
  /// [model] - The model used.
  /// [success] - Whether the request succeeded.
  void recordRequest({required String model, required bool success});

  /// Record request latency.
  ///
  /// [model] - The model used.
  /// [latency] - Request duration.
  void recordLatency({required String model, required Duration latency});

  /// Record token usage.
  ///
  /// [model] - The model used.
  /// [promptTokens] - Number of tokens in the prompt.
  /// [generatedTokens] - Number of tokens generated.
  void recordTokens({
    required String model,
    required int promptTokens,
    required int generatedTokens,
  });

  /// Record an error.
  ///
  /// [model] - The model used.
  /// [errorType] - Type of error (e.g., 'timeout', 'api_error', 'network_error').
  void recordError({required String model, required String errorType});

  /// Get current metrics snapshot.
  ///
  /// Returns a map of metric names to values.
  Map<String, dynamic> getMetrics();

  /// Reset all metrics.
  void reset();
}

/// Default implementation of [LLMMetrics] that tracks basic statistics.
///
/// This implementation keeps simple counters and averages in memory.
/// For production use, consider implementing a more sophisticated
/// metrics collector that integrates with your observability stack.
class DefaultLLMMetrics implements LLMMetrics {
  final Map<String, _ModelMetrics> _metrics = {};

  @override
  void recordRequest({required String model, required bool success}) {
    final metrics = _metrics.putIfAbsent(model, () => _ModelMetrics());
    metrics.totalRequests++;
    if (success) {
      metrics.successfulRequests++;
    } else {
      metrics.failedRequests++;
    }
  }

  @override
  void recordLatency({required String model, required Duration latency}) {
    final metrics = _metrics.putIfAbsent(model, () => _ModelMetrics());
    metrics.totalLatency += latency;
    metrics.requestCount++;
    metrics.latencies.add(latency.inMilliseconds);
    // Keep only last 1000 latencies for percentile calculation
    if (metrics.latencies.length > 1000) {
      metrics.latencies.removeAt(0);
    }
  }

  @override
  void recordTokens({
    required String model,
    required int promptTokens,
    required int generatedTokens,
  }) {
    final metrics = _metrics.putIfAbsent(model, () => _ModelMetrics());
    metrics.totalPromptTokens += promptTokens;
    metrics.totalGeneratedTokens += generatedTokens;
  }

  @override
  void recordError({required String model, required String errorType}) {
    final metrics = _metrics.putIfAbsent(model, () => _ModelMetrics());
    metrics.errors[errorType] = (metrics.errors[errorType] ?? 0) + 1;
  }

  @override
  Map<String, dynamic> getMetrics() {
    final result = <String, dynamic>{};
    for (final entry in _metrics.entries) {
      final model = entry.key;
      final metrics = entry.value;

      result['$model.total_requests'] = metrics.totalRequests;
      result['$model.successful_requests'] = metrics.successfulRequests;
      result['$model.failed_requests'] = metrics.failedRequests;
      result['$model.total_prompt_tokens'] = metrics.totalPromptTokens;
      result['$model.total_generated_tokens'] = metrics.totalGeneratedTokens;

      if (metrics.requestCount > 0) {
        final avgLatency = metrics.totalLatency.inMilliseconds / metrics.requestCount;
        result['$model.avg_latency_ms'] = avgLatency;

        if (metrics.latencies.isNotEmpty) {
          final sorted = List<int>.from(metrics.latencies)..sort();
          final p50Index = (sorted.length * 0.5).floor();
          final p95Index = (sorted.length * 0.95).floor();
          final p99Index = (sorted.length * 0.99).floor();

          result['$model.p50_latency_ms'] = sorted[p50Index.clamp(0, sorted.length - 1)];
          result['$model.p95_latency_ms'] = sorted[p95Index.clamp(0, sorted.length - 1)];
          result['$model.p99_latency_ms'] = sorted[p99Index.clamp(0, sorted.length - 1)];
        }
      }

      result['$model.errors'] = Map<String, int>.from(metrics.errors);
    }
    return result;
  }

  @override
  void reset() {
    _metrics.clear();
  }
}

class _ModelMetrics {
  int totalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int totalPromptTokens = 0;
  int totalGeneratedTokens = 0;
  Duration totalLatency = Duration.zero;
  int requestCount = 0;
  final List<int> latencies = [];
  final Map<String, int> errors = {};
}
