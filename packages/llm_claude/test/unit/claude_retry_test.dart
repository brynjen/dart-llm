import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeChatRepository retry', () {
    test('retry config is applied', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      final repo = ClaudeChatRepository(
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
      final repo = ClaudeChatRepository(
        apiKey: 'test-key',
        timeoutConfig: timeoutConfig,
      );

      expect(repo.timeoutConfig, timeoutConfig);
    });
  });
}
