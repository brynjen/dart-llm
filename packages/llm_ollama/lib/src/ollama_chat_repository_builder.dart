import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';

import 'ollama_chat_repository.dart';

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
class OllamaChatRepositoryBuilder {
  String? _baseUrl;
  int? _maxToolAttempts;
  RetryConfig? _retryConfig;
  TimeoutConfig? _timeoutConfig;
  http.Client? _httpClient;

  /// Set the base URL of the Ollama server.
  OllamaChatRepositoryBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Set the maximum number of tool attempts.
  OllamaChatRepositoryBuilder maxToolAttempts(int maxToolAttempts) {
    _maxToolAttempts = maxToolAttempts;
    return this;
  }

  /// Set the retry configuration.
  OllamaChatRepositoryBuilder retryConfig(RetryConfig retryConfig) {
    _retryConfig = retryConfig;
    return this;
  }

  /// Set the timeout configuration.
  OllamaChatRepositoryBuilder timeoutConfig(TimeoutConfig timeoutConfig) {
    _timeoutConfig = timeoutConfig;
    return this;
  }

  /// Set a custom HTTP client.
  OllamaChatRepositoryBuilder httpClient(http.Client httpClient) {
    _httpClient = httpClient;
    return this;
  }

  /// Build the [OllamaChatRepository] instance.
  OllamaChatRepository build() {
    return OllamaChatRepository(
      baseUrl: _baseUrl ?? 'http://localhost:11434',
      maxToolAttempts: _maxToolAttempts ?? 25,
      retryConfig: _retryConfig,
      timeoutConfig: _timeoutConfig,
      httpClient: _httpClient,
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
