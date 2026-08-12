import 'package:llm_core/llm_core.dart';

/// Configuration for a single vLLM server instance within a [VLLMPool].
class VLLMInstanceConfig {
  const VLLMInstanceConfig({
    required this.baseUrl,
    this.apiKey,
    this.maxConcurrent = 3,
    this.exclusiveModels = const [],
    this.preferredModels = const [],
    this.preferEmbedding = false,
    this.retryConfig,
    this.timeoutConfig,
    this.maxToolAttempts = 90,
  }) : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  /// The base URL of this vLLM instance, for example `http://localhost:8000`.
  final String baseUrl;

  /// Optional API key for this vLLM instance.
  final String? apiKey;

  /// Maximum number of simultaneous requests for this instance.
  final int maxConcurrent;

  /// Hard affinity: only these exact model names will be routed here.
  ///
  /// When empty, the instance accepts all models.
  final List<String> exclusiveModels;

  /// Soft affinity: these models are preferred on this instance, but the pool
  /// may fall back to other eligible instances.
  final List<String> preferredModels;

  /// When `true`, [VLLMPool.embed] calls are routed here before trying
  /// non-embedding instances.
  final bool preferEmbedding;

  /// Per-instance retry configuration.
  final RetryConfig? retryConfig;

  /// Per-instance timeout configuration.
  final TimeoutConfig? timeoutConfig;

  /// Maximum tool-call loop iterations for requests on this instance.
  final int maxToolAttempts;

  /// Returns `true` if this instance is eligible to handle [model].
  bool acceptsModel(String model) {
    if (exclusiveModels.isEmpty) return true;
    return exclusiveModels.contains(model);
  }

  /// Returns `true` if this instance has a soft preference for [model].
  bool prefersModel(String model) => preferredModels.contains(model);
}
