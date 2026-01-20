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

    test('copyWith with all field combinations', () {
      const original = StreamChatOptions();
      const retryConfig = RetryConfig();
      final tool = TestTool(
        toolName: 'test',
        toolDescription: 'Test tool',
        toolParameters: [],
      );

      // Copy with think
      final withThink = original.copyWith(think: true);
      expect(withThink.think, true);
      expect(withThink.tools, isEmpty);

      // Copy with tools
      final withTools = original.copyWith(tools: [tool]);
      expect(withTools.tools.length, 1);
      expect(withTools.think, false);

      // Copy with extra
      final withExtra = original.copyWith(extra: {'key': 'value'});
      expect(withExtra.extra, {'key': 'value'});

      // Copy with toolAttempts
      final withAttempts = original.copyWith(toolAttempts: 5);
      expect(withAttempts.toolAttempts, 5);

      // Copy with timeout
      final withTimeout = original.copyWith(
        timeout: const Duration(minutes: 10),
      );
      expect(withTimeout.timeout, const Duration(minutes: 10));

      // Copy with retryConfig
      final withRetry = original.copyWith(retryConfig: retryConfig);
      expect(withRetry.retryConfig, retryConfig);

      // Copy with multiple fields
      final withMultiple = original.copyWith(
        think: true,
        tools: [tool],
        extra: {'key': 'value'},
        toolAttempts: 5,
        timeout: const Duration(minutes: 10),
        retryConfig: retryConfig,
      );
      expect(withMultiple.think, true);
      expect(withMultiple.tools.length, 1);
      expect(withMultiple.extra, {'key': 'value'});
      expect(withMultiple.toolAttempts, 5);
      expect(withMultiple.timeout, const Duration(minutes: 10));
      expect(withMultiple.retryConfig, retryConfig);
    });

    test('copyWith null handling', () {
      const original = StreamChatOptions(
        think: true,
        toolAttempts: 5,
        timeout: Duration(minutes: 5),
      );

      // copyWith doesn't support nulling fields, but we test that original is unchanged
      final copied = original.copyWith(think: false);
      expect(original.think, true);
      expect(copied.think, false);
      expect(copied.toolAttempts, 5); // Other fields preserved
    });
  });
}

// Helper class for testing
class TestTool extends LLMTool {
  TestTool({
    required this.toolName,
    required this.toolDescription,
    required this.toolParameters,
  });

  final String toolName;
  final String toolDescription;
  final List<LLMToolParam> toolParameters;

  @override
  String get name => toolName;

  @override
  String get description => toolDescription;

  @override
  List<LLMToolParam> get parameters => toolParameters;

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return 'result';
  }
}
