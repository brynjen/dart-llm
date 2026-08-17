import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('gptIsReasoningModel', () {
    test('classifies reasoning families', () {
      for (final model in [
        'o1',
        'o1-mini',
        'o3',
        'o3-mini-2025-01-31',
        'o4-mini',
        'gpt-5',
        'gpt-5-nano',
        'gpt-5.1',
        'gpt-5.2-codex-max',
        'GPT-5 ', // case/whitespace tolerant
      ]) {
        expect(gptIsReasoningModel(model), isTrue, reason: model);
      }
    });

    test('conventional and unknown models are NOT reasoning', () {
      // Unknown defaults to conventional: sending reasoning_effort to a
      // non-reasoning model is a hard 400, omitting it is safe.
      for (final model in [
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4.1',
        'gpt-5-chat-latest',
        'some-future-model',
      ]) {
        expect(gptIsReasoningModel(model), isFalse, reason: model);
      }
    });
  });

  group('gptSupportsReasoningEffort', () {
    test('o1-mini and o1-preview reject the parameter', () {
      expect(gptSupportsReasoningEffort('o1-mini'), isFalse);
      expect(gptSupportsReasoningEffort('o1-preview'), isFalse);
      expect(gptSupportsReasoningEffort('o1'), isTrue);
      expect(gptSupportsReasoningEffort('o3-mini'), isTrue);
      expect(gptSupportsReasoningEffort('gpt-5'), isTrue);
      expect(gptSupportsReasoningEffort('gpt-4o'), isFalse);
    });
  });

  group('gptRejectsSamplingParams', () {
    test('matches reasoning-model classification', () {
      expect(gptRejectsSamplingParams('gpt-5'), isTrue);
      expect(gptRejectsSamplingParams('o3'), isTrue);
      expect(gptRejectsSamplingParams('gpt-4o'), isFalse);
    });
  });

  group('gptEffortWireValue', () {
    test('o-series clamps to low/medium/high', () {
      expect(gptEffortWireValue('o3', ReasoningEffort.none), 'low');
      expect(gptEffortWireValue('o3', ReasoningEffort.minimal), 'low');
      expect(gptEffortWireValue('o3', ReasoningEffort.low), 'low');
      expect(gptEffortWireValue('o3', ReasoningEffort.medium), 'medium');
      expect(gptEffortWireValue('o3', ReasoningEffort.high), 'high');
      expect(gptEffortWireValue('o3', ReasoningEffort.xhigh), 'high');
      expect(gptEffortWireValue('o3', ReasoningEffort.max), 'high');
    });

    test('original gpt-5 generation supports minimal, not none', () {
      expect(gptEffortWireValue('gpt-5', ReasoningEffort.none), 'minimal');
      expect(gptEffortWireValue('gpt-5', ReasoningEffort.minimal), 'minimal');
      expect(gptEffortWireValue('gpt-5-nano', ReasoningEffort.low), 'low');
      expect(gptEffortWireValue('gpt-5', ReasoningEffort.xhigh), 'high');
    });

    test('gpt-5.1+ supports none, not minimal', () {
      expect(gptEffortWireValue('gpt-5.1', ReasoningEffort.none), 'none');
      expect(gptEffortWireValue('gpt-5.1', ReasoningEffort.minimal), 'low');
      expect(gptEffortWireValue('gpt-5.1', ReasoningEffort.xhigh), 'high');
    });

    test('xhigh passes through only on codex-max ids', () {
      expect(
        gptEffortWireValue('gpt-5.1-codex-max', ReasoningEffort.xhigh),
        'xhigh',
      );
      expect(
        gptEffortWireValue('gpt-5.1-codex-max', ReasoningEffort.max),
        'xhigh',
      );
      expect(gptEffortWireValue('gpt-5.1', ReasoningEffort.max), 'high');
    });

    test('null for models without the parameter', () {
      expect(gptEffortWireValue('gpt-4o', ReasoningEffort.high), isNull);
      expect(gptEffortWireValue('o1-mini', ReasoningEffort.high), isNull);
    });
  });
}
