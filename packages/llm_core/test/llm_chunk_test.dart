import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMChunk', () {
    test('construction with all fields', () {
      final chunk = LLMChunk(
        model: 'gpt-4o',
        createdAt: DateTime(2024, 1, 1),
        message: LLMChunkMessage(content: 'Hello', role: LLMRole.assistant),
        done: true,
        promptEvalCount: 10,
        evalCount: 5,
        status: 'complete',
      );

      expect(chunk.model, 'gpt-4o');
      expect(chunk.createdAt, DateTime(2024, 1, 1));
      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.role, LLMRole.assistant);
      expect(chunk.done, true);
      expect(chunk.promptEvalCount, 10);
      expect(chunk.evalCount, 5);
      expect(chunk.status, 'complete');
    });

    test('construction with minimal fields', () {
      final chunk = LLMChunk(
        model: 'gpt-4o',
        createdAt: DateTime(2024, 1, 1),
        message: LLMChunkMessage(content: 'Hello', role: LLMRole.assistant),
      );

      expect(chunk.model, 'gpt-4o');
      expect(chunk.done, null);
      expect(chunk.promptEvalCount, null);
      expect(chunk.evalCount, null);
      expect(chunk.status, null);
    });

    test('construction with null message', () {
      final chunk = LLMChunk(
        model: 'gpt-4o',
        createdAt: DateTime(2024, 1, 1),
        message: null,
      );

      expect(chunk.message, null);
    });

    test('construction with thinking content', () {
      final chunk = LLMChunk(
        model: 'gpt-4o',
        createdAt: DateTime(2024, 1, 1),
        message: LLMChunkMessage(
          content: 'Hello',
          role: LLMRole.assistant,
          thinking: 'I should greet the user',
        ),
      );

      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.thinking, 'I should greet the user');
    });

    test('construction with tool calls', () {
      final chunk = LLMChunk(
        model: 'gpt-4o',
        createdAt: DateTime(2024, 1, 1),
        message: LLMChunkMessage(
          content: null,
          role: LLMRole.assistant,
          toolCalls: [
            LLMToolCall(
              id: 'call_1',
              name: 'calculator',
              arguments: '{"a": 2, "b": 2}',
            ),
          ],
        ),
      );

      expect(chunk.message?.toolCalls, isNotNull);
      expect(chunk.message?.toolCalls?.length, 1);
      expect(chunk.message?.toolCalls?.first.name, 'calculator');
    });
  });

  group('LLMChunkMessage', () {
    test('construction with all fields', () {
      final message = LLMChunkMessage(
        content: 'Hello',
        role: LLMRole.assistant,
        thinking: 'I should greet',
        toolCallId: 'call_1',
        images: ['image1'],
        toolCalls: [LLMToolCall(id: 'call_1', name: 'tool', arguments: '{}')],
      );

      expect(message.content, 'Hello');
      expect(message.role, LLMRole.assistant);
      expect(message.thinking, 'I should greet');
      expect(message.toolCallId, 'call_1');
      expect(message.images, ['image1']);
      expect(message.toolCalls?.length, 1);
    });

    test('construction with minimal fields', () {
      final message = LLMChunkMessage(
        content: 'Hello',
        role: LLMRole.assistant,
      );

      expect(message.content, 'Hello');
      expect(message.role, LLMRole.assistant);
      expect(message.thinking, null);
      expect(message.toolCallId, null);
      expect(message.images, null);
      expect(message.toolCalls, null);
    });

    test('construction with null content', () {
      final message = LLMChunkMessage(content: null, role: LLMRole.assistant);

      expect(message.content, null);
    });

    test('construction with null role', () {
      final message = LLMChunkMessage(content: 'Hello', role: null);

      expect(message.role, null);
    });
  });
}
