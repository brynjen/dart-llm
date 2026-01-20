import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('ChatGPTChatRepository', () {
    test('creates with required apiKey', () {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');
      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://api.openai.com');
      expect(repo.maxToolAttempts, 25);
    });

    test('creates with custom configuration', () {
      final retryConfig = RetryConfig(maxAttempts: 5);
      final timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );

      final repo = ChatGPTChatRepository(
        apiKey: 'test-key',
        baseUrl: 'https://custom.openai.com',
        maxToolAttempts: 10,
        retryConfig: retryConfig,
        timeoutConfig: timeoutConfig,
      );

      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder creates repository correctly', () {
      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-key')
          .baseUrl('https://custom.openai.com')
          .maxToolAttempts(15)
          .retryConfig(RetryConfig(maxAttempts: 3))
          .build();

      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
    });

    test('builder requires apiKey', () {
      expect(
        () => ChatGPTChatRepositoryBuilder().build(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ChatGPTChatRepository validation', () {
    test('validates model name', () async {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');

      await expectLater(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('validates messages', () async {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');

      await expectLater(
        repo.streamChat('test-model', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });
  });
}
