import 'package:llm_core/llm_core.dart';
import 'package:llm_gemini/src/gemini_chat_repository.dart';

/// Builder for creating [GeminiChatRepository] instances.
///
/// Example:
/// ```dart
/// final repo = GeminiChatRepository.builder()
///   .apiKey('your-api-key')
///   .maxToolAttempts(10)
///   .retryConfig(RetryConfig(maxAttempts: 3))
///   .build();
/// ```
class GeminiChatRepositoryBuilder
    extends ChatRepositoryBuilderBase<GeminiChatRepositoryBuilder> {
  String? _apiKey;
  String? _baseUrl;

  /// Set the Google API key.
  GeminiChatRepositoryBuilder apiKey(String apiKey) {
    _apiKey = apiKey;
    return this;
  }

  /// Set the base URL for the Gemini API.
  GeminiChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  @override
  GeminiChatRepository build() {
    if (_apiKey == null) {
      throw ArgumentError('API key is required');
    }
    return GeminiChatRepository(
      apiKey: _apiKey!,
      baseUrl: _baseUrl ?? 'https://generativelanguage.googleapis.com',
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
