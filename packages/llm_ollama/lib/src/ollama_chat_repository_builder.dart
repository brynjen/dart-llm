import 'package:llm_core/llm_core.dart';

import 'package:llm_ollama/src/ollama_chat_repository.dart';

/// Builder for creating [OllamaChatRepository] instances with complex configurations.
///
/// Example:
/// ```dart
/// final repo = OllamaChatRepository.builder()
///   .baseUrl('http://localhost:11434')
///   .maxToolAttempts(10)
///   .timeoutConfig(TimeoutConfig(
///     connectionTimeout: Duration(seconds: 5),
///     readTimeout: Duration(minutes: 3),
///   ))
///   .retryConfig(RetryConfig(maxAttempts: 5))
///   .httpClient(customClient)
///   .build();
/// ```
class OllamaChatRepositoryBuilder
    extends ChatRepositoryBuilderBase<OllamaChatRepositoryBuilder> {
  String? _baseUrl;

  /// Set the base URL of the Ollama server.
  OllamaChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  @override
  OllamaChatRepository build() {
    return OllamaChatRepository(
      baseUrl: _baseUrl ?? 'http://localhost:11434',
      maxToolAttempts: maxToolAttemptsValue,
      retryConfig: retryConfigValue,
      timeoutConfig: timeoutConfigValue,
      httpClient: httpClientValue,
    );
  }
}

/// Extension to add builder method to [OllamaChatRepository].
extension OllamaChatRepositoryBuilderExtension on OllamaChatRepository {
  /// Create a builder for configuring a new repository instance.
  static OllamaChatRepositoryBuilder builder() {
    return OllamaChatRepositoryBuilder();
  }
}
