import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('chatResponse', () {
    test('collects complete response from stream', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('Hello, world!');
      mock.setTokenCounts(promptTokens: 5, generatedTokens: 3);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      expect(response.content, 'Hello, world!');
      expect(response.model, 'test-model');
      expect(response.promptEvalCount, 5);
      expect(response.evalCount, 3);
      expect(response.done, true);
    });

    test('handles tool calls in response', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('I will calculate that');
      mock.setToolCalls([
        LLMToolCall(
          id: 'call_1',
          name: 'calculator',
          arguments: '{"a": 2, "b": 2}',
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'What is 2+2?')],
      );

      expect(response.toolCalls, isNotNull);
      expect(response.toolCalls!.length, 1);
      expect(response.toolCalls!.first.name, 'calculator');
    });

    test('propagates errors from stream', () async {
      final mock = MockLLMChatRepository();
      mock.setError(const LLMApiException('API error', statusCode: 500));

      expect(
        () => mock.chatResponse(
          'test-model',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        throwsA(isA<LLMApiException>()),
      );
    });
  });
}
