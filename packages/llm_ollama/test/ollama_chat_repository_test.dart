import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaChatRepository', () {
    test('creates with default values', () {
      final repo = OllamaChatRepository();
      expect(repo.baseUrl, 'http://localhost:11434');
      expect(repo.maxToolAttempts, 25);
    });

    test('creates with custom configuration', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );

      final repo = OllamaChatRepository(
        baseUrl: 'http://custom:8080',
        maxToolAttempts: 10,
        retryConfig: retryConfig,
        timeoutConfig: timeoutConfig,
      );

      expect(repo.baseUrl, 'http://custom:8080');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder creates repository correctly', () {
      final repo = OllamaChatRepositoryBuilder()
          .baseUrl('http://test:8080')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .build();

      expect(repo.baseUrl, 'http://test:8080');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
    });
  });

  group('OllamaChatRepository validation', () {
    test('validates model name', () async {
      final repo = OllamaChatRepository();

      // Validation happens when the stream is listened to
      await expectLater(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('validates messages', () async {
      final repo = OllamaChatRepository();

      await expectLater(
        repo.streamChat('test-model', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });
  });
}
