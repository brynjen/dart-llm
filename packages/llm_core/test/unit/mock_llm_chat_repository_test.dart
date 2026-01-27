import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('MockLLMChatRepository', () {
    test('streams response content', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('Hello, world!');

      final stream = mock.streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      final StringBuffer content = StringBuffer();
      await for (final chunk in stream) {
        content.write(chunk.message?.content ?? '');
      }

      expect(content.toString(), 'Hello, world!');
    });

    test('streams tool calls', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('I will calculate');
      mock.setToolCalls([
        LLMToolCall(id: 'call_1', name: 'calculator', arguments: '{}'),
      ]);

      final stream = mock.streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'What is 2+2?')],
      );

      List<LLMToolCall>? toolCalls;
      await for (final chunk in stream) {
        if (chunk.done ?? false) {
          toolCalls = chunk.message?.toolCalls;
        }
      }

      expect(toolCalls, isNotNull);
      expect(toolCalls!.length, 1);
      expect(toolCalls.first.name, 'calculator');
    });

    test('propagates errors', () async {
      final mock = MockLLMChatRepository();
      mock.setError(const LLMApiException('API error', statusCode: 500));

      final stream = mock.streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      expect(() async {
        await for (final _ in stream) {}
      }, throwsA(isA<LLMApiException>()));
    });

    test('generates embeddings', () async {
      final mock = MockLLMChatRepository();

      final embeddings = await mock.embed(
        model: 'test-model',
        messages: ['Hello', 'World'],
      );

      expect(embeddings.length, 2);
      expect(embeddings[0].embedding.length, 128);
      expect(embeddings[0].model, 'test-model');
    });
  });
}
