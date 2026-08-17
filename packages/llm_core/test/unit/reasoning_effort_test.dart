import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('reasoningEffortForBudget', () {
    test('maps budgets onto the canonical bands', () {
      final expectations = <int, ReasoningEffort>{
        -1: ReasoningEffort.none,
        0: ReasoningEffort.none,
        1: ReasoningEffort.minimal,
        512: ReasoningEffort.minimal,
        513: ReasoningEffort.low,
        2048: ReasoningEffort.low,
        2049: ReasoningEffort.medium,
        8192: ReasoningEffort.medium,
        8193: ReasoningEffort.high,
        24576: ReasoningEffort.high,
        24577: ReasoningEffort.xhigh,
        49152: ReasoningEffort.xhigh,
        49153: ReasoningEffort.max,
        1000000: ReasoningEffort.max,
      };
      expectations.forEach((budget, effort) {
        expect(reasoningEffortForBudget(budget), effort, reason: '$budget');
      });
    });
  });

  group('LLMChatOptions.reasoningEffort', () {
    test('defaults to null', () {
      expect(const LLMChatOptions().reasoningEffort, isNull);
    });

    test('copyWith preserves when not passed', () {
      const options = LLMChatOptions(reasoningEffort: ReasoningEffort.high);
      expect(
        options.copyWith(think: true).reasoningEffort,
        ReasoningEffort.high,
      );
    });

    test('copyWith sets and explicitly clears', () {
      const options = LLMChatOptions(reasoningEffort: ReasoningEffort.high);
      expect(
        options.copyWith(reasoningEffort: ReasoningEffort.low).reasoningEffort,
        ReasoningEffort.low,
      );
      expect(options.copyWith(reasoningEffort: null).reasoningEffort, isNull);
    });
  });

  group('StreamChatOptionsMerger', () {
    test('reasoningEffort flows into MergedOptions', () {
      final merged = StreamChatOptionsMerger.merge(
        options: const LLMChatOptions(reasoningEffort: ReasoningEffort.xhigh),
      );
      expect(merged.reasoningEffort, ReasoningEffort.xhigh);
    });

    test('null without options', () {
      expect(StreamChatOptionsMerger.merge().reasoningEffort, isNull);
    });
  });

  group('CacheKeyGenerator', () {
    test('reasoningEffort changes the options hash', () {
      const a = LLMChatOptions(reasoningEffort: ReasoningEffort.low);
      const b = LLMChatOptions(reasoningEffort: ReasoningEffort.high);
      const unset = LLMChatOptions();
      expect(
        CacheKeyGenerator.optionsHash(a),
        isNot(CacheKeyGenerator.optionsHash(b)),
      );
      expect(
        CacheKeyGenerator.optionsHash(a),
        isNot(CacheKeyGenerator.optionsHash(unset)),
      );
    });
  });

  group('LLMUsage.reasoningTokens', () {
    test('optional and defaults to null', () {
      const usage = LLMUsage(promptTokens: 1, completionTokens: 2);
      expect(usage.reasoningTokens, isNull);
      expect(
        const LLMUsage(
          promptTokens: 1,
          completionTokens: 2,
          reasoningTokens: 5,
        ).reasoningTokens,
        5,
      );
    });
  });
}
