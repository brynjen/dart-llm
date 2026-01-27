import 'package:llm_core/llm_core.dart';

import 'package:llm_chatgpt/src/chatgpt_chat_repository.dart';

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
class ChatGPTChatRepositoryBuilder
    extends ChatRepositoryBuilderBase<ChatGPTChatRepositoryBuilder> {
  String? _apiKey;
  String? _baseUrl;

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

  @override
  ChatGPTChatRepository build() {
    if (_apiKey == null) {
      throw ArgumentError('API key is required');
    }
    return ChatGPTChatRepository(
      apiKey: _apiKey!,
      baseUrl: _baseUrl ?? 'https://api.openai.com',
      maxToolAttempts: maxToolAttemptsValue,
      retryConfig: retryConfigValue,
      timeoutConfig: timeoutConfigValue,
      httpClient: httpClientValue,
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
