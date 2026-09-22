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

  group('MergedOptions.toChatOptions', () {
    test('forwards every option the merge resolved', () {
      final merged = StreamChatOptionsMerger.merge(
        options: const LLMChatOptions(
          think: true,
          autoExecuteTools: false,
          backendOptions: {'top_k': 20},
          timeout: Duration(seconds: 12),
          responseFormat: JsonFormat(),
          temperature: 0.3,
          topP: 0.8,
          topK: 40,
          maxOutputTokens: 256,
          stopSequences: ['STOP'],
          reasoningBudget: 512,
          reasoningEffort: ReasoningEffort.high,
          useCache: true,
          cacheTtl: Duration(minutes: 5),
          recordMetrics: false,
          usagePerChunk: true,
        ),
      );

      final child = merged.toChatOptions();

      expect(child.think, isTrue);
      expect(child.autoExecuteTools, isFalse);
      expect(child.backendOptions, {'top_k': 20});
      expect(child.timeout, const Duration(seconds: 12));
      expect(child.responseFormat, isA<JsonFormat>());
      expect(child.temperature, 0.3);
      expect(child.topP, 0.8);
      expect(child.topK, 40);
      expect(child.maxOutputTokens, 256);
      expect(child.stopSequences, ['STOP']);
      expect(child.reasoningBudget, 512);
      expect(child.reasoningEffort, ReasoningEffort.high);
      expect(child.usagePerChunk, isTrue);

      // These three were dropped by every backend's hand-written rebuild, so a
      // tool loop silently lost caching and metrics preferences from round two.
      expect(child.useCache, isTrue, reason: 'useCache must survive a round');
      expect(child.cacheTtl, const Duration(minutes: 5));
      expect(child.recordMetrics, isFalse);
    });

    test('overrides carry the round own values', () {
      final merged = StreamChatOptionsMerger.merge(
        options: const LLMChatOptions(
          extra: 'parent',
          toolAttempts: 9,
          backendOptions: {'topK': 20},
        ),
      );

      final child = merged.toChatOptions(
        tools: const [],
        extra: 'child',
        toolAttempts: 3,
        retryConfig: const RetryConfig(maxAttempts: 2),
        backendOptions: const {'top_k': 20},
      );

      expect(child.extra, 'child');
      expect(child.toolAttempts, 3);
      expect(child.retryConfig?.maxAttempts, 2);
      // vLLM passes its normalized map so aliases are not re-expanded.
      expect(child.backendOptions, {'top_k': 20});
    });

    test('unset overrides fall back to the merged values', () {
      final merged = StreamChatOptionsMerger.merge(
        options: const LLMChatOptions(extra: 'parent', toolAttempts: 9),
      );

      final child = merged.toChatOptions();

      expect(child.extra, 'parent');
      expect(child.toolAttempts, 9);
    });

    test('usagePerChunk survives into the next tool round', () {
      final merged = StreamChatOptionsMerger.merge(
        options: const LLMChatOptions(usagePerChunk: true),
      );

      expect(merged.usagePerChunk, isTrue);
      expect(merged.toChatOptions(toolAttempts: 2).usagePerChunk, isTrue);
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
