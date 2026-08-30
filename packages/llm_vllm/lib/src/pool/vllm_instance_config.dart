import 'package:http/http.dart' as http;
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
    this.rateLimiter,
    this.supportedParams,
    this.capabilities,
    this.extraHeaders,
    this.httpClient,
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

  /// Per-instance rate limit, applied on top of the pool's concurrency
  /// controls. Instance-scoped because it protects a specific server.
  final RateLimiter? rateLimiter;

  /// Request parameters this server accepts, from
  /// `VLLMRepository.fetchSupportedParams()`. Instance-scoped because pooled
  /// servers may run different vLLM versions.
  final Set<String>? supportedParams;

  /// What this deployment offers, from
  /// `VLLMRepository.resolveCapabilities()`. Feeds the pool's
  /// `capabilitiesForModel` aggregation.
  final LLMCapabilities? capabilities;

  /// Extra headers sent with every request to this instance, including its
  /// health checks. The protocol headers and `authorization` always win.
  final Map<String, String>? extraHeaders;

  /// Optional HTTP client for this instance.
  ///
  /// A client supplied here is **not** closed by `VLLMPool.dispose()` — its
  /// owner disposes it, matching `VLLMChatRepository.close()` semantics.
  /// Leave `null` to let the pooled repository own (and close) its client.
  final http.Client? httpClient;

  /// Returns `true` if this instance is eligible to handle [model].
  bool acceptsModel(String model) {
    if (exclusiveModels.isEmpty) return true;
    return exclusiveModels.contains(model);
  }

  /// Returns `true` if this instance has a soft preference for [model].
  bool prefersModel(String model) => preferredModels.contains(model);
}
