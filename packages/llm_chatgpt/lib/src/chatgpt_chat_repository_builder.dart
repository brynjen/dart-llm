import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';

import 'chatgpt_chat_repository.dart';

/// Builder for creating [ChatGPTChatRepository] instances with complex configurations.
///
/// Example:
/// ```dart
/// final repo = ChatGPTChatRepository.builder()
///   .apiKey('your-api-key')
///   .baseUrl('https://api.openai.com')
///   .maxToolAttempts(10)
///   .timeoutConfig(TimeoutConfig(
///     connectionTimeout: Duration(seconds: 5),
///     readTimeout: Duration(minutes: 3),
///   ))
///   .retryConfig(RetryConfig(maxAttempts: 5))
///   .httpClient(customClient)
///   .build();
/// ```
class ChatGPTChatRepositoryBuilder {
  String? _apiKey;
  String? _baseUrl;
  int? _maxToolAttempts;
  RetryConfig? _retryConfig;
  TimeoutConfig? _timeoutConfig;
  http.Client? _httpClient;

  /// Set the API key for OpenAI.
  ChatGPTChatRepositoryBuilder apiKey(String apiKey) {
    _apiKey = apiKey;
    return this;
  }

  /// Set the base URL for the OpenAI API.
  ChatGPTChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Set the maximum number of tool attempts.
  ChatGPTChatRepositoryBuilder maxToolAttempts(int maxToolAttempts) {
    _maxToolAttempts = maxToolAttempts;
    return this;
  }

  /// Set the retry configuration.
  ChatGPTChatRepositoryBuilder retryConfig(RetryConfig retryConfig) {
    _retryConfig = retryConfig;
    return this;
  }

  /// Set the timeout configuration.
  ChatGPTChatRepositoryBuilder timeoutConfig(TimeoutConfig timeoutConfig) {
    _timeoutConfig = timeoutConfig;
    return this;
  }

  /// Set a custom HTTP client.
  ChatGPTChatRepositoryBuilder httpClient(http.Client httpClient) {
    _httpClient = httpClient;
    return this;
  }

  /// Build the [ChatGPTChatRepository] instance.
  ChatGPTChatRepository build() {
    if (_apiKey == null) {
      throw ArgumentError('API key is required');
    }
    return ChatGPTChatRepository(
      apiKey: _apiKey!,
      baseUrl: _baseUrl ?? 'https://api.openai.com',
      maxToolAttempts: _maxToolAttempts ?? 25,
      retryConfig: _retryConfig,
      timeoutConfig: _timeoutConfig,
      httpClient: _httpClient,
    );
  }
}

/// Extension to add builder method to [ChatGPTChatRepository].
extension ChatGPTChatRepositoryBuilderExtension on ChatGPTChatRepository {
  /// Create a builder for configuring a new repository instance.
  static ChatGPTChatRepositoryBuilder builder() {
    return ChatGPTChatRepositoryBuilder();
  }
}
