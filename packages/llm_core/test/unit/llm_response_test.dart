import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
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
      expect(response.role, 'assistant');
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
