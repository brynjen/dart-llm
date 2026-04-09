import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiChatRepository retry', () {
    test('retry config is applied', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      final repo = GeminiChatRepository(
        apiKey: 'test-key',
        retryConfig: retryConfig,
      );

      expect(repo.retryConfig, retryConfig);
      expect(repo.retryConfig?.maxAttempts, 5);
    });

    test('timeout config is applied', () {
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );
      final repo = GeminiChatRepository(
        apiKey: 'test-key',
        timeoutConfig: timeoutConfig,
      );

      expect(repo.timeoutConfig, timeoutConfig);
    });
  });
}
