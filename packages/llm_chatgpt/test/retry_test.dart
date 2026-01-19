import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('ChatGPTChatRepository retry', () {
    test('retry config is applied', () {
      final retryConfig = RetryConfig(maxAttempts: 5);
      final repo = ChatGPTChatRepository(
        apiKey: 'test-key',
        retryConfig: retryConfig,
      );

      expect(repo.retryConfig, retryConfig);
      expect(repo.retryConfig?.maxAttempts, 5);
    });

    test('timeout config is applied', () {
      final timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );
      final repo = ChatGPTChatRepository(
        apiKey: 'test-key',
        timeoutConfig: timeoutConfig,
      );

      expect(repo.timeoutConfig, timeoutConfig);
    });
  });
}
