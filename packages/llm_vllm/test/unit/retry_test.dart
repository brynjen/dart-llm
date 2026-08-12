import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMChatRepository retry', () {
    test('retry config is applied', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      final repo = VLLMChatRepository(retryConfig: retryConfig);

      expect(repo.retryConfig, retryConfig);
      expect(repo.retryConfig?.maxAttempts, 5);
    });

    test('timeout config is applied', () {
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );
      final repo = VLLMChatRepository(timeoutConfig: timeoutConfig);

      expect(repo.timeoutConfig, timeoutConfig);
    });
  });
}
