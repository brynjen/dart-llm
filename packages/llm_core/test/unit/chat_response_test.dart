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

    test('keeps token counts from a trailing usage-only chunk', () async {
      // Several backends end a turn with two `done` chunks: the finish reason
      // first, then a frame carrying only usage. Assigning counts
      // unconditionally on every done chunk meant whichever arrived last won,
      // so a count-less finish chunk erased real numbers.
      final mock = MockLLMChatRepository();
      mock.setStreamChunks([
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime(2026),
          done: false,
          message: LLMChunkMessage(content: 'Hi', role: LLMRole.assistant),
        ),
        // Usage arrives first here, finish reason second.
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime(2026),
          done: true,
          promptEvalCount: 11,
          evalCount: 22,
          usage: const LLMUsage(
            promptTokens: 11,
            completionTokens: 22,
            totalTokens: 33,
          ),
          message: null,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime(2026),
          done: true,
          finishReason: LLMFinishReason.stop,
          message: LLMChunkMessage(content: null, role: LLMRole.assistant),
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      expect(response.content, 'Hi');
      expect(response.promptEvalCount, 11);
      expect(response.evalCount, 22);
      expect(response.usage.totalTokens, 33);
      expect(response.finishReason, LLMFinishReason.stop);
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

    test('collects complete response with tool calls', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('The answer is 4');
      mock.setToolCalls([
        LLMToolCall(
          id: 'call_1',
          name: 'calculator',
          arguments: '{"a": 2, "b": 2}',
        ),
      ]);
      mock.setTokenCounts(promptTokens: 10, generatedTokens: 5);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'What is 2+2?')],
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
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      expect(response.content, '');
      expect(response.done, true);
    });

    test('handles thinking content', () async {
      final mock = MockLLMChatRepository();
      mock.setStreamChunks([
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: null,
            thinking: 'I should answer briefly. ',
            role: LLMRole.assistant,
          ),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: 'Response',
            role: LLMRole.assistant,
          ),
          done: true,
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        think: true,
      );

      expect(response.content, 'Response');
      expect(response.thinking, 'I should answer briefly. ');
    });

    test('preserves final chunk usage and provider metadata', () async {
      final mock = MockLLMChatRepository();
      mock.setStreamChunks([
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: 'Done', role: LLMRole.assistant),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: null, role: LLMRole.assistant),
          done: true,
          usage: const LLMUsage(promptTokens: 7, completionTokens: 3),
          finishReason: LLMFinishReason.length,
          providerMetadata: const {'request_id': 'req_123'},
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      expect(response.content, 'Done');
      expect(response.promptEvalCount, 7);
      expect(response.evalCount, 3);
      expect(response.usage.totalTokens, 10);
      expect(response.finishReason, LLMFinishReason.length);
      expect(response.doneReason, 'length');
      expect(response.providerMetadata, {'request_id': 'req_123'});
    });

    test('excludes tool-result chunk content from response.content', () async {
      final mock = MockLLMChatRepository();
      mock.setStreamChunks([
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: 'Answer ', role: LLMRole.assistant),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: 'TOOL_DATA', role: LLMRole.tool),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: '42', role: LLMRole.assistant),
          done: true,
          promptEvalCount: 2,
          evalCount: 2,
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Question')],
      );

      expect(response.content, 'Answer 42');
    });

    test(
      'strict mode throws when tool loop has no final assistant answer',
      () async {
        final mock = MockLLMChatRepository();
        mock.setStreamChunks([
          LLMChunk(
            model: 'test-model',
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: null,
              role: LLMRole.assistant,
              toolCalls: [
                LLMToolCall(
                  id: 'call_1',
                  name: 'calculator',
                  arguments: '{"a":2,"b":2}',
                ),
              ],
            ),
            done: true,
            promptEvalCount: 5,
            evalCount: 2,
          ),
          LLMChunk(
            model: 'test-model',
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: 'Result: 4',
              role: LLMRole.tool,
              toolCallId: 'call_1',
            ),
            done: false,
          ),
        ]);

        expect(
          () => mock.chatResponse(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: '2+2')],
            options: const StreamChatOptions(),
          ),
          throwsA(isA<ToolLoopIncompleteException>()),
        );
      },
    );

    test('accepts streamed assistant content after a tool loop', () async {
      final mock = MockLLMChatRepository();
      mock.setStreamChunks([
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: 'Result: 4',
            role: LLMRole.tool,
            toolCallId: 'call_1',
          ),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: 'The answer is 4.',
            role: LLMRole.assistant,
          ),
          done: false,
        ),
        LLMChunk(
          model: 'test-model',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: null, role: null),
          done: true,
          promptEvalCount: 5,
          evalCount: 4,
        ),
      ]);

      final response = await mock.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: '2+2')],
      );

      expect(response.content, 'The answer is 4.');
    });
  });
}
