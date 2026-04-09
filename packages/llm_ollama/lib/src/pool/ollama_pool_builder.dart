import 'package:llm_ollama/src/pool/health_check_config.dart';
import 'package:llm_ollama/src/pool/ollama_instance_config.dart';
import 'package:llm_ollama/src/pool/ollama_model_config.dart';
import 'package:llm_ollama/src/pool/ollama_pool.dart';

/// Fluent builder for creating [OllamaPool] instances.
///
/// Example:
/// ```dart
/// final pool = OllamaPool.builder()
///   .addInstance(OllamaInstanceConfig(
///     baseUrl: 'http://gpu1:11434',
///     maxConcurrent: 3,
///     preferredModels: ['qwen3:4b'],
///     preferEmbedding: true,
///   ))
///   .addInstance(OllamaInstanceConfig(
///     baseUrl: 'http://gpu2:11434',
///     maxConcurrent: 1,
///     exclusiveModels: ['llama3.3:70b'],
///   ))
///   .addModelConfig(OllamaModelConfig(
///     pattern: 'llama3.3:70b',
///     maxConcurrent: 1,
///     exclusive: true,
///     keepAlive: Duration.zero,
///   ))
///   .healthCheck(HealthCheckConfig())
///   .queueTimeout(Duration(seconds: 30))
///   .build();
/// ```
class OllamaPoolBuilder {
  final _instances = <OllamaInstanceConfig>[];
  final _modelConfigs = <OllamaModelConfig>[];
  HealthCheckConfig? _healthCheck;
  Duration? _queueTimeout;
  int? _maxQueueDepth;

  /// Adds a single [OllamaInstanceConfig] to the pool.
  OllamaPoolBuilder addInstance(OllamaInstanceConfig config) {
    _instances.add(config);
    return this;
  }

  /// Replaces all instance configurations at once.
  OllamaPoolBuilder instances(List<OllamaInstanceConfig> configs) {
    _instances
      ..clear()
      ..addAll(configs);
    return this;
  }

  /// Adds a [OllamaModelConfig] constraint.
  OllamaPoolBuilder addModelConfig(OllamaModelConfig config) {
    _modelConfigs.add(config);
    return this;
  }

  /// Replaces all model configurations at once.
  OllamaPoolBuilder modelConfigs(List<OllamaModelConfig> configs) {
    _modelConfigs
      ..clear()
      ..addAll(configs);
    return this;
  }

  /// Enables background health checking with the given [config].
  OllamaPoolBuilder healthCheck(HealthCheckConfig config) {
    _healthCheck = config;
    return this;
  }

  /// Sets a timeout for requests waiting in the queue.
  ///
  /// When a request waits longer than [timeout], an
  /// [OllamaQueueTimeoutException] is thrown. Default: no timeout.
  OllamaPoolBuilder queueTimeout(Duration timeout) {
    _queueTimeout = timeout;
    return this;
  }

  /// Sets the maximum total number of requests that may queue across all
  /// instances before new requests are rejected with [OllamaQueueFullException].
  ///
  /// Default: unbounded.
  OllamaPoolBuilder maxQueueDepth(int depth) {
    _maxQueueDepth = depth;
    return this;
  }

  /// Builds and returns the configured [OllamaPool].
  OllamaPool build() {
    assert(
      _instances.isNotEmpty,
      'Add at least one instance before calling build()',
    );
    return OllamaPool(
      instances: List.unmodifiable(_instances),
      modelConfigs: List.unmodifiable(_modelConfigs),
      healthCheck: _healthCheck,
      queueTimeout: _queueTimeout,
      maxQueueDepth: _maxQueueDepth,
    );
  }
}
