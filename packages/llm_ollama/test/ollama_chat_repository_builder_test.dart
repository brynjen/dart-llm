import 'package:http/http.dart' as http;
import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaChatRepositoryBuilder', () {
    test('all builder methods', () {
      final httpClient = http.Client();
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
      );

      final repo = OllamaChatRepositoryBuilder()
          .baseUrl('http://custom:8080')
          .maxToolAttempts(10)
          .retryConfig(retryConfig)
          .timeoutConfig(timeoutConfig)
          .httpClient(httpClient)
          .build();

      expect(repo.baseUrl, 'http://custom:8080');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder with partial configuration', () {
      final repo = OllamaChatRepositoryBuilder()
          .baseUrl('http://custom:8080')
          .build();

      expect(repo.baseUrl, 'http://custom:8080');
      expect(repo.maxToolAttempts, 25); // Default
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder with no configuration uses defaults', () {
      final repo = OllamaChatRepositoryBuilder().build();

      expect(repo.baseUrl, 'http://localhost:11434');
      expect(repo.maxToolAttempts, 25);
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder method chaining', () {
      final repo = OllamaChatRepositoryBuilder()
          .baseUrl('http://test:8080')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .timeoutConfig(const TimeoutConfig(readTimeout: Duration(minutes: 5)))
          .build();

      expect(repo.baseUrl, 'http://test:8080');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
      expect(repo.timeoutConfig?.readTimeout, Duration(minutes: 5));
    });

    test('builder extension method', () {
      final builder = OllamaChatRepositoryBuilderExtension.builder();
      expect(builder, isA<OllamaChatRepositoryBuilder>());
    });
  });
}
