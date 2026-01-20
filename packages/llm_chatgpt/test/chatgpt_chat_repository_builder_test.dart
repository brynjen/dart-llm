import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('ChatGPTChatRepositoryBuilder', () {
    test('all builder methods', () {
      final httpClient = http.Client();
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
      );

      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.openai.com')
          .maxToolAttempts(10)
          .retryConfig(retryConfig)
          .timeoutConfig(timeoutConfig)
          .httpClient(httpClient)
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder validation - apiKey required', () {
      expect(
        () => ChatGPTChatRepositoryBuilder().build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('builder with partial configuration', () {
      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.openai.com')
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 25); // Default
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder with no configuration uses defaults', () {
      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-api-key')
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://api.openai.com');
      expect(repo.maxToolAttempts, 25);
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder method chaining', () {
      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-api-key')
          .baseUrl('https://custom.openai.com')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .timeoutConfig(const TimeoutConfig(readTimeout: Duration(minutes: 5)))
          .build();

      expect(repo.apiKey, 'test-api-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
      expect(repo.timeoutConfig?.readTimeout, Duration(minutes: 5));
    });

    test('builder extension method', () {
      final builder = ChatGPTChatRepositoryBuilderExtension.builder();
      expect(builder, isA<ChatGPTChatRepositoryBuilder>());
    });
  });
}
