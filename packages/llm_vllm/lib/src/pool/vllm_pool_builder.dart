import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/pool/health_check_config.dart';
import 'package:llm_vllm/src/pool/vllm_instance_config.dart';
import 'package:llm_vllm/src/pool/vllm_model_config.dart';
import 'package:llm_vllm/src/pool/vllm_pool.dart';

/// Fluent builder for creating [VLLMPool] instances.
///
/// Example:
/// ```dart
/// final pool = VLLMPool.builder()
///   .addInstance(VLLMInstanceConfig(
///     baseUrl: 'http://gpu1:8000',
///     maxConcurrent: 3,
///     preferredModels: ['qwen3:4b'],
///     preferEmbedding: true,
///   ))
///   .addInstance(VLLMInstanceConfig(
///     baseUrl: 'http://gpu2:8000',
///     maxConcurrent: 1,
///     exclusiveModels: ['llama3.3:70b'],
///   ))
///   .addModelConfig(VLLMModelConfig(
///     pattern: 'llama3.3:70b',
///     maxConcurrent: 1,
///     exclusive: true,
///   ))
///   .healthCheck(HealthCheckConfig())
///   .queueTimeout(Duration(seconds: 30))
///   .build();
/// ```
class VLLMPoolBuilder {
  final _instances = <VLLMInstanceConfig>[];
  final _modelConfigs = <VLLMModelConfig>[];
  HealthCheckConfig? _healthCheck;
  Duration? _queueTimeout;
  int? _maxQueueDepth;
  ResponseCache? _responseCache;
  LLMMetrics? _metrics;

  /// Adds a single [VLLMInstanceConfig] to the pool.
  VLLMPoolBuilder addInstance(VLLMInstanceConfig config) {
    _instances.add(config);
    return this;
  }

  /// Replaces all instance configurations at once.
  VLLMPoolBuilder instances(List<VLLMInstanceConfig> configs) {
    _instances
      ..clear()
      ..addAll(configs);
    return this;
  }

  /// Adds a [VLLMModelConfig] constraint.
  VLLMPoolBuilder addModelConfig(VLLMModelConfig config) {
    _modelConfigs.add(config);
    return this;
  }

  /// Replaces all model configurations at once.
  VLLMPoolBuilder modelConfigs(List<VLLMModelConfig> configs) {
    _modelConfigs
      ..clear()
      ..addAll(configs);
    return this;
  }

  /// Enables background health checking with the given [config].
  VLLMPoolBuilder healthCheck(HealthCheckConfig config) {
    _healthCheck = config;
    return this;
  }

  /// Sets a timeout for requests waiting in the queue.
  ///
  /// When a request waits longer than [timeout], an
  /// [VLLMQueueTimeoutException] is thrown. Default: no timeout.
  VLLMPoolBuilder queueTimeout(Duration timeout) {
    _queueTimeout = timeout;
    return this;
  }

  /// Sets the maximum total number of requests that may queue across all
  /// instances before new requests are rejected with [VLLMQueueFullException].
  ///
  /// Default: unbounded.
  VLLMPoolBuilder maxQueueDepth(int depth) {
    _maxQueueDepth = depth;
    return this;
  }

  /// Sets a pool-level response cache (see [VLLMPool.responseCache]).
  VLLMPoolBuilder responseCache(ResponseCache cache) {
    _responseCache = cache;
    return this;
  }

  /// Sets a pool-level metrics collector (see [VLLMPool.metrics]).
  VLLMPoolBuilder metrics(LLMMetrics metrics) {
    _metrics = metrics;
    return this;
  }

  /// Builds and returns the configured [VLLMPool].
  VLLMPool build() {
    assert(
      _instances.isNotEmpty,
      'Add at least one instance before calling build()',
    );
    return VLLMPool(
      instances: List.unmodifiable(_instances),
      modelConfigs: List.unmodifiable(_modelConfigs),
      healthCheck: _healthCheck,
      queueTimeout: _queueTimeout,
      maxQueueDepth: _maxQueueDepth,
      responseCache: _responseCache,
      metrics: _metrics,
    );
  }
}
