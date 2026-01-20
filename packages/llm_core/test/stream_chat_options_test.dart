import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('StreamChatOptions', () {
    test('default values are correct', () {
      const options = StreamChatOptions();
      expect(options.think, false);
      expect(options.tools, isEmpty);
      expect(options.extra, null);
      expect(options.toolAttempts, null);
      expect(options.timeout, null);
      expect(options.retryConfig, null);
    });

    test('copyWith creates new instance with changed fields', () {
      const original = StreamChatOptions();
      final copied = original.copyWith(think: true);

      expect(original.think, false);
      expect(copied.think, true);
    });

    test('can be created with all parameters', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      const options = StreamChatOptions(
        think: true,
        extra: {'key': 'value'},
        toolAttempts: 10,
        timeout: Duration(minutes: 5),
        retryConfig: retryConfig,
      );

      expect(options.think, true);
      expect(options.toolAttempts, 10);
      expect(options.timeout, const Duration(minutes: 5));
      expect(options.retryConfig, retryConfig);
    });
  });
}
