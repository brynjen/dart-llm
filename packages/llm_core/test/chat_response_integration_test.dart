import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('chatResponse integration', () {
    test('collects complete response with tool calls', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('The answer is 4');
      mock.setToolCalls([
        LLMToolCall(id: 'call_1', name: 'calculator', arguments: '{"a": 2, "b": 2}'),
      ]);
      mock.setTokenCounts(promptTokens: 10, generatedTokens: 5);

      final response = await mock.chatResponse(
        'test-model',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
        ],
        tools: [],
      );

      expect(response.content, 'The answer is 4');
      expect(response.model, 'test-model');
      expect(response.promptEvalCount, 10);
      expect(response.evalCount, 5);
      expect(response.toolCalls, isNotNull);
      expect(response.toolCalls!.length, 1);
    });

    test('handles empty response', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('');

      final response = await mock.chatResponse(
        'test-model',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Hello'),
        ],
      );

      expect(response.content, '');
      expect(response.done, true);
    });

    test('handles thinking content', () async {
      final mock = MockLLMChatRepository();
      // Mock doesn't support thinking yet, but test structure
      mock.setResponse('Response');

      final response = await mock.chatResponse(
        'test-model',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Hello'),
        ],
        think: true,
      );

      expect(response.content, 'Response');
    });
  });
}
