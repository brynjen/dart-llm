import 'package:llm_core/llm_core.dart';
import 'package:llm_claude/src/claude_chat_repository.dart';

/// Builder for creating [ClaudeChatRepository] instances.
///
/// Example:
/// ```dart
/// final repo = ClaudeChatRepository.builder()
///   .apiKey('your-api-key')
///   .maxToolAttempts(10)
///   .retryConfig(RetryConfig(maxAttempts: 3))
///   .build();
/// ```
class ClaudeChatRepositoryBuilder
    extends ChatRepositoryBuilderBase<ClaudeChatRepositoryBuilder> {
  String? _apiKey;
  String? _baseUrl;
  Map<String, String>? _extraHeaders;

  /// Set the Anthropic API key.
  ClaudeChatRepositoryBuilder apiKey(String apiKey) {
    _apiKey = apiKey;
    return this;
  }

  /// Set the base URL for the Anthropic API.
  ClaudeChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Set extra headers sent with every request, such as `anthropic-beta`.
  ///
  /// The protocol headers, `x-api-key` and `anthropic-version` always take
  /// precedence.
  ClaudeChatRepositoryBuilder extraHeaders(Map<String, String> headers) {
    _extraHeaders = headers;
    return this;
  }

  @override
  ClaudeChatRepository build() {
    if (_apiKey == null) {
      throw ArgumentError('API key is required');
    }
    return ClaudeChatRepository(
      apiKey: _apiKey!,
      baseUrl: _baseUrl ?? 'https://api.anthropic.com',
      extraHeaders: _extraHeaders,
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
