import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  _finishReasonResolutionTests();

  group('LLMResponse', () {
    test('construction with all fields', () {
      final response = LLMResponse(
        model: 'gpt-4o',
        createdAt: DateTime(2024),
        role: 'assistant',
        content: 'Hello, world!',
        done: true,
        doneReason: 'stop',
        promptEvalCount: 10,
        evalCount: 5,
        toolCalls: [
          LLMToolCall(
            id: 'call_1',
            name: 'calculator',
            arguments: '{"a": 2, "b": 2}',
          ),
        ],
      );

      expect(response.model, 'gpt-4o');
      expect(response.createdAt, DateTime(2024));
      expect(response.role, LLMRole.assistant);
      expect(response.roleName, 'assistant');
      expect(response.usage.promptTokens, 10);
      expect(response.usage.completionTokens, 5);
      expect(response.finishReason, LLMFinishReason.stop);
      expect(response.content, 'Hello, world!');
      expect(response.done, true);
      expect(response.doneReason, 'stop');
      expect(response.promptEvalCount, 10);
      expect(response.evalCount, 5);
      expect(response.toolCalls?.length, 1);
    });

    test('construction with null content', () {
      final response = LLMResponse(
        model: 'gpt-4o',
        createdAt: DateTime(2024),
        role: 'assistant',
        content: null,
        done: true,
        doneReason: 'tool_calls',
        promptEvalCount: 10,
        evalCount: 0,
        toolCalls: [
          LLMToolCall(id: 'call_1', name: 'calculator', arguments: '{}'),
        ],
      );

      expect(response.content, null);
      expect(response.doneReason, 'tool_calls');
      expect(response.toolCalls, isNotNull);
    });

    test('construction with null tool calls', () {
      final response = LLMResponse(
        model: 'gpt-4o',
        createdAt: DateTime(2024),
        role: 'assistant',
        content: 'Hello',
        done: true,
        doneReason: 'stop',
        promptEvalCount: 10,
        evalCount: 5,
        toolCalls: null,
      );

      expect(response.toolCalls, null);
    });

    test('construction with empty tool calls list', () {
      final response = LLMResponse(
        model: 'gpt-4o',
        createdAt: DateTime(2024),
        role: 'assistant',
        content: 'Hello',
        done: true,
        doneReason: 'stop',
        promptEvalCount: 10,
        evalCount: 5,
        toolCalls: [],
      );

      expect(response.toolCalls, isEmpty);
    });

    test('construction with different done reasons', () {
      final reasons = ['stop', 'length', 'tool_calls', 'content_filter'];

      for (final reason in reasons) {
        final response = LLMResponse(
          model: 'gpt-4o',
          createdAt: DateTime(2024),
          role: 'assistant',
          content: 'Hello',
          done: true,
          doneReason: reason,
          promptEvalCount: 10,
          evalCount: 5,
          toolCalls: null,
        );

        expect(response.doneReason, reason);
      }
    });

    test('construction with zero token counts', () {
      final response = LLMResponse(
        model: 'gpt-4o',
        createdAt: DateTime(2024),
        role: 'assistant',
        content: 'Hello',
        done: true,
        doneReason: 'stop',
        promptEvalCount: 0,
        evalCount: 0,
        toolCalls: null,
      );

      expect(response.promptEvalCount, 0);
      expect(response.evalCount, 0);
    });
  });
}

void _finishReasonResolutionTests() {
  group('LLMFinishReason.resolve', () {
    test('passes the reported reason through when no calls were parsed', () {
      for (final reported in [...LLMFinishReason.values, null]) {
        expect(
          LLMFinishReason.resolve(
            reported: reported,
            hasCompleteToolCalls: false,
          ),
          reported,
          reason: '$reported must survive untouched without tool calls',
        );
      }
    });

    test('upgrades the reasons that do not contradict an executable call', () {
      // `stop` is the case every provider gets wrong: vLLM on a named
      // tool_choice, Ollama's native API, OpenAI intermittently. `unknown`
      // covers a spelling this library has not seen yet — a terminal frame
      // carrying complete calls is a tool-call turn whatever it was called.
      for (final reported in [
        LLMFinishReason.stop,
        LLMFinishReason.unknown,
        LLMFinishReason.toolCalls,
      ]) {
        expect(
          LLMFinishReason.resolve(
            reported: reported,
            hasCompleteToolCalls: true,
          ),
          LLMFinishReason.toolCalls,
          reason: '$reported carrying complete calls is a tool-call turn',
        );
      }
    });

    test('never overwrites a reason that contradicts the call', () {
      // `length` truncated the arguments mid-JSON, so the call is not
      // executable and the caller must see the truncation. `contentFilter` and
      // `refusal` are the values a caller checks before trusting a response;
      // hiding one behind `toolCalls` would bury a safety outcome.
      for (final reported in [
        LLMFinishReason.length,
        LLMFinishReason.contentFilter,
        LLMFinishReason.refusal,
      ]) {
        expect(
          LLMFinishReason.resolve(
            reported: reported,
            hasCompleteToolCalls: true,
          ),
          reported,
          reason: '$reported must not be reclassified as a tool-call turn',
        );
      }
    });

    test('classifies a turn the provider gave no reason for at all', () {
      // llama.cpp reports nothing; complete calls are the only signal there is.
      expect(
        LLMFinishReason.resolve(reported: null, hasCompleteToolCalls: true),
        LLMFinishReason.toolCalls,
      );
    });

    test('canBecomeToolCalls covers every enum member', () {
      // Guards the exhaustive switch: a new member must be classified, not
      // silently inherit a default.
      for (final reason in LLMFinishReason.values) {
        expect(reason.canBecomeToolCalls, isA<bool>());
      }
      expect(LLMFinishReason.stop.canBecomeToolCalls, isTrue);
      expect(LLMFinishReason.length.canBecomeToolCalls, isFalse);
    });
  });
}
