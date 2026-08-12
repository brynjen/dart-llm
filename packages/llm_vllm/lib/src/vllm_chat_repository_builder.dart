import 'package:llm_core/llm_core.dart';

import 'package:llm_vllm/src/vllm_chat_repository.dart';

/// Builder for creating [VLLMChatRepository] instances with complex configurations.
///
/// Example:
/// ```dart
/// final repo = VLLMChatRepository.builder()
///   .baseUrl('http://localhost:8000')
///   .apiKey('optional-vllm-key')
///   .maxToolAttempts(10)
///   .timeoutConfig(TimeoutConfig(
///     connectionTimeout: Duration(seconds: 5),
///     readTimeout: Duration(minutes: 3),
///   ))
///   .retryConfig(RetryConfig(maxAttempts: 5))
///   .httpClient(customClient)
///   .build();
/// ```
class VLLMChatRepositoryBuilder
    extends ChatRepositoryBuilderBase<VLLMChatRepositoryBuilder> {
  String? _baseUrl;
  String? _apiKey;

  /// Set the base URL of the VLLM server.
  VLLMChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Set the optional API key for vLLM servers started with `--api-key`.
  VLLMChatRepositoryBuilder apiKey(String apiKey) {
    _apiKey = apiKey;
    return this;
  }

  @override
  VLLMChatRepository build() {
    return VLLMChatRepository(
      baseUrl: _baseUrl ?? 'http://localhost:8000',
      apiKey: _apiKey,
      maxToolAttempts: maxToolAttemptsValue,
      retryConfig: retryConfigValue,
      timeoutConfig: timeoutConfigValue,
      rateLimiter: rateLimiterValue,
      responseCache: responseCacheValue,
      metrics: metricsValue,
      httpClient: httpClientValue,
    );
  }
}

/// Extension to add builder method to [VLLMChatRepository].
extension VLLMChatRepositoryBuilderExtension on VLLMChatRepository {
  /// Create a builder for configuring a new repository instance.
  static VLLMChatRepositoryBuilder builder() {
    return VLLMChatRepositoryBuilder();
  }
}
