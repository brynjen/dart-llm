import 'package:llm_core/llm_core.dart';

/// Controls how embedding requests are handled when an instance also serves
/// chat models that may be occupying VRAM.
enum EmbeddingIsolation {
  /// No special handling. Ollama manages model swapping internally.
  none,

  /// Inject `keep_alive: '0'` into embedding requests so the embedding model
  /// is unloaded immediately after use, freeing VRAM for the next chat model
  /// reload. Best for instances with a single large chat model.
  unloadFirst,

  /// Expect a dedicated instance tagged with [OllamaInstanceConfig.preferEmbedding].
  /// The pool routes all [embed] calls to that instance; no model swapping occurs.
  dedicated,
}

/// Configuration for a single Ollama server instance within an [OllamaPool].
///
/// Example — two GPUs, one large and one small:
/// ```dart
/// OllamaPool(
///   instances: [
///     OllamaInstanceConfig(
///       baseUrl: 'http://bigcard:11434',
///       maxConcurrent: 1,
///       exclusiveModels: ['llama3.3:70b'],
///       embeddingIsolation: EmbeddingIsolation.unloadFirst,
///     ),
///     OllamaInstanceConfig(
///       baseUrl: 'http://smallcard:11434',
///       maxConcurrent: 4,
///       preferredModels: ['qwen3:4b', 'llama3.2:3b'],
///       preferEmbedding: true,
///     ),
///   ],
/// )
/// ```
class OllamaInstanceConfig {
  const OllamaInstanceConfig({
    required this.baseUrl,
    this.maxConcurrent = 3,
    this.exclusiveModels = const [],
    this.preferredModels = const [],
    this.preferEmbedding = false,
    this.embeddingIsolation = EmbeddingIsolation.unloadFirst,
    this.retryConfig,
    this.timeoutConfig,
    this.maxToolAttempts = 90,
  }) : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  /// The base URL of this Ollama instance (e.g. `'http://localhost:11434'`).
  final String baseUrl;

  /// Maximum number of simultaneous requests for this instance.
  ///
  /// Ollama's own guidance: keep this at 3–4 for general use. Set to 1 for
  /// instances running large models that fill the GPU.
  final int maxConcurrent;

  /// Hard affinity: only these exact model names will be routed here.
  ///
  /// Any request for a model NOT in this list is rejected at routing time and
  /// sent to other instances. Leave empty to accept all models.
  final List<String> exclusiveModels;

  /// Soft affinity: these models are preferred on this instance, but the pool
  /// will fall back to other instances if this one is at capacity.
  final List<String> preferredModels;

  /// When `true`, [embed] calls are routed here before trying non-embedding
  /// instances. Useful for a dedicated embedding card or smaller GPU.
  final bool preferEmbedding;

  /// How embedding requests are isolated on this instance.
  ///
  /// Defaults to [EmbeddingIsolation.unloadFirst], which injects
  /// `keep_alive: '0'` so the embedding model frees VRAM immediately.
  final EmbeddingIsolation embeddingIsolation;

  /// Per-instance retry configuration. Overrides the pool default if set.
  final RetryConfig? retryConfig;

  /// Per-instance timeout configuration. Overrides the pool default if set.
  final TimeoutConfig? timeoutConfig;

  /// Maximum tool-call loop iterations for requests on this instance.
  final int maxToolAttempts;

  /// Returns `true` if this instance is eligible to handle [model].
  ///
  /// When [exclusiveModels] is empty, all models are accepted.
  bool acceptsModel(String model) {
    if (exclusiveModels.isEmpty) return true;
    return exclusiveModels.contains(model);
  }

  /// Returns `true` if this instance has a soft preference for [model].
  bool prefersModel(String model) => preferredModels.contains(model);
}
