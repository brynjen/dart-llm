import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('StreamChatOptions', () {
    test('default values are correct', () {
      final options = StreamChatOptions();
      expect(options.think, false);
      expect(options.tools, isEmpty);
      expect(options.extra, null);
      expect(options.toolAttempts, null);
      expect(options.timeout, null);
      expect(options.retryConfig, null);
    });

    test('copyWith creates new instance with changed fields', () {
      final original = StreamChatOptions(think: false);
      final copied = original.copyWith(think: true);
      
      expect(original.think, false);
      expect(copied.think, true);
    });

    test('can be created with all parameters', () {
      final retryConfig = RetryConfig(maxAttempts: 5);
      final options = StreamChatOptions(
        think: true,
        tools: [],
        extra: {'key': 'value'},
        toolAttempts: 10,
        timeout: Duration(minutes: 5),
        retryConfig: retryConfig,
      );

      expect(options.think, true);
      expect(options.toolAttempts, 10);
      expect(options.timeout, Duration(minutes: 5));
      expect(options.retryConfig, retryConfig);
    });
  });
}
