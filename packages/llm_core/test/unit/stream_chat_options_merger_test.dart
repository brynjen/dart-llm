import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('StreamChatOptionsMerger', () {
    test('uses individual parameters when options are not provided', () {
      final merged = StreamChatOptionsMerger.merge(
        think: true,
        tools: [TestTool()],
        extra: const {'session': 'abc'},
        toolAttempts: 7,
        autoExecuteTools: false,
        backendOptions: const {'format': 'json'},
      );

      expect(merged.think, isTrue);
      expect(merged.tools.length, 1);
      expect(merged.extra, const {'session': 'abc'});
      expect(merged.toolAttempts, 7);
      expect(merged.autoExecuteTools, isFalse);
      expect(merged.backendOptions, const {'format': 'json'});
    });

    test('options take precedence over individual parameters', () {
      final merged = StreamChatOptionsMerger.merge(
        extra: const {'session': 'fallback'},
        toolAttempts: 2,
        backendOptions: const {'format': 'text'},
        options: const StreamChatOptions(
          think: true,
          toolAttempts: 5,
          autoExecuteTools: false,
          backendOptions: {'format': 'json', 'keep_alive': '5m'},
        ),
      );

      expect(merged.think, isTrue);
      expect(merged.toolAttempts, 5);
      expect(merged.autoExecuteTools, isFalse);
      expect(merged.backendOptions, const {
        'format': 'json',
        'keep_alive': '5m',
      });
    });

    test('options tools replace individual tools when explicitly provided', () {
      final withEmptyOptionsTools = StreamChatOptionsMerger.merge(
        tools: [TestTool()],
        options: const StreamChatOptions(),
      );
      expect(withEmptyOptionsTools.tools.length, 1);

      final withExplicitEmptyOptionsTools = StreamChatOptionsMerger.merge(
        tools: [TestTool()],
        options: const StreamChatOptions(tools: []),
      );
      expect(withExplicitEmptyOptionsTools.tools, isEmpty);

      final withOptionsTools = StreamChatOptionsMerger.merge(
        options: StreamChatOptions(tools: [TestTool()]),
      );
      expect(withOptionsTools.tools.length, 1);
    });

    test('merges per-request timeout and retry config', () {
      const retryConfig = RetryConfig(maxAttempts: 2);
      final merged = StreamChatOptionsMerger.merge(
        options: const StreamChatOptions(
          timeout: Duration(seconds: 15),
          retryConfig: retryConfig,
        ),
      );

      expect(merged.timeout, const Duration(seconds: 15));
      expect(merged.retryConfig, retryConfig);
    });
  });
}

class TestTool extends LLMTool {
  @override
  String get name => 'test_tool';

  @override
  String get description => 'test';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return 'ok';
  }
}
