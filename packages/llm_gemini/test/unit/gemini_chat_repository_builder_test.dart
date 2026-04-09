import 'package:http/http.dart' as http;
import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiChatRepositoryBuilder', () {
    test('all builder methods', () {
      final httpClient = http.Client();
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
      );

      final repo = GeminiChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.gemini.com')
          .maxToolAttempts(10)
          .retryConfig(retryConfig)
          .timeoutConfig(timeoutConfig)
          .httpClient(httpClient)
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.gemini.com');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder validation - apiKey required', () {
      expect(
        () => GeminiChatRepositoryBuilder().build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('builder with partial configuration', () {
      final repo = GeminiChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.gemini.com')
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.gemini.com');
      expect(repo.maxToolAttempts, 90); // Default
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder with no configuration uses defaults', () {
      final repo = GeminiChatRepositoryBuilder().apiKey('test-api-key').build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://generativelanguage.googleapis.com');
      expect(repo.maxToolAttempts, 90);
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder method chaining', () {
      final repo = GeminiChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.gemini.com')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .timeoutConfig(const TimeoutConfig(readTimeout: Duration(minutes: 5)))
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.gemini.com');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
      expect(repo.timeoutConfig?.readTimeout, const Duration(minutes: 5));
    });
  });
}
