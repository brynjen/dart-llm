import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('GPTResponse', () {
    test('fromJson and toJson roundtrip - complete response', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'Hello!'},
            'finish_reason': 'stop',
            'logprobs': null,
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
        'system_fingerprint': 'fp_abc123',
      };

      final response = GPTResponse.fromJson(json);
      final reconstructed = response.toJson();

      expect(response.id, 'chatcmpl-123');
      expect(response.model, 'gpt-4o');
      expect(response.choices.length, 1);
      expect(response.choices[0].message.content, 'Hello!');
      expect(response.usage.promptTokens, 10);
      expect(response.systemFingerprint, 'fp_abc123');

      // Verify toJson structure
      expect(reconstructed['id'], 'chatcmpl-123');
      expect(reconstructed['model'], 'gpt-4o');
    });

    test('fromJson with tool calls', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'calculator',
                    'arguments': '{"a": 2, "b": 2}',
                  },
                  'index': 0,
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      };

      final response = GPTResponse.fromJson(json);

      expect(response.choices[0].message.toolCalls, isNotNull);
      expect(response.choices[0].message.toolCalls?.length, 1);
      expect(
        response.choices[0].message.toolCalls?.first.function.name,
        'calculator',
      );
    });

    test('fromJson without system fingerprint', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'Hello!'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      };

      final response = GPTResponse.fromJson(json);

      expect(response.systemFingerprint, null);
    });
  });

  group('GPTChoice', () {
    test('fromJson and toJson', () {
      final json = {
        'index': 0,
        'message': {'role': 'assistant', 'content': 'Hello!'},
        'finish_reason': 'stop',
        'logProbs': null,
      };

      final choice = GPTChoice.fromJson(json);
      final reconstructed = choice.toJson();

      expect(choice.index, 0);
      expect(choice.message.content, 'Hello!');
      expect(choice.finishReason, 'stop');
      expect(reconstructed['index'], 0);
    });
  });

  group('GPTMessage', () {
    test('fromJson and toJson with content', () {
      final json = {'role': 'assistant', 'content': 'Hello!'};

      final message = GPTMessage.fromJson(json);
      final reconstructed = message.toJson();

      expect(message.role, 'assistant');
      expect(message.content, 'Hello!');
      expect(reconstructed['role'], 'assistant');
      expect(reconstructed['content'], 'Hello!');
    });

    test('fromJson with tool calls', () {
      final json = {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'calculator', 'arguments': '{}'},
            'index': 0,
          },
        ],
      };

      final message = GPTMessage.fromJson(json);

      expect(message.toolCalls, isNotNull);
      expect(message.toolCalls?.length, 1);
    });

    test('fromJson with refusal', () {
      final json = {
        'role': 'assistant',
        'content': null,
        'refusal': 'I cannot help with that.',
      };

      final message = GPTMessage.fromJson(json);

      expect(message.refusal, 'I cannot help with that.');
    });
  });

  group('GPTToolCall', () {
    test('fromJson and toJson', () {
      final json = {
        'id': 'call_1',
        'type': 'function',
        'function': {'name': 'calculator', 'arguments': '{"a": 2, "b": 2}'},
        'index': 0,
      };

      final toolCall = GPTToolCall.fromJson(json);
      final reconstructed = toolCall.toJson();

      expect(toolCall.id, 'call_1');
      expect(toolCall.type, 'function');
      expect(toolCall.index, 0);
      expect(toolCall.function.name, 'calculator');
      expect(reconstructed['id'], 'call_1');
    });

    test('copyWith merges arguments', () {
      final original = GPTToolCall(
        id: 'call_1',
        index: 0,
        type: 'function',
        function: GPTToolFunctionCall(name: 'calculator', arguments: '{"a": 2'),
      );

      final newChunk = GPTChunk(
        id: 'chatcmpl-123',
        created: DateTime.now(),
        model: 'gpt-4o',
        systemFingerprint: null,
        choices: [
          GPTChunkChoice(
            index: 0,
            delta: GPTChunkChoiceDelta(
              role: null,
              content: null,
              toolCalls: [
                GPTToolCall(
                  id: 'call_1',
                  index: 0,
                  type: 'function',
                  function: GPTToolFunctionCall(
                    name: 'calculator',
                    arguments: ', "b": 2}',
                  ),
                ),
              ],
            ),
            logProbs: null,
            finishReason: null,
          ),
        ],
      );

      final merged = original.copyWith(
        newFunction: newChunk.choices[0].delta.toolCalls![0].function,
      );

      expect(merged.function.arguments, '{"a": 2, "b": 2}');
    });
  });

  group('GPTToolFunctionCall', () {
    test('fromJson and toJson', () {
      final json = {'name': 'calculator', 'arguments': '{"a": 2, "b": 2}'};

      final functionCall = GPTToolFunctionCall.fromJson(json);
      final reconstructed = functionCall.toJson();

      expect(functionCall.name, 'calculator');
      expect(functionCall.arguments, '{"a": 2, "b": 2}');
      expect(reconstructed['name'], 'calculator');
      expect(reconstructed['arguments'], '{"a": 2, "b": 2}');
    });

    test('fromJson with empty arguments', () {
      final json = {'name': 'calculator'};

      final functionCall = GPTToolFunctionCall.fromJson(json);

      expect(functionCall.arguments, '');
    });

    test('copyWith appends arguments', () {
      final original = GPTToolFunctionCall(
        name: 'calculator',
        arguments: '{"a": 2',
      );

      final merged = original.copyWith(newArguments: ', "b": 2}');

      expect(merged.name, 'calculator');
      expect(merged.arguments, '{"a": 2, "b": 2}');
    });
  });

  group('GPTUsage', () {
    test('fromJson and toJson with usage token details', () {
      final json = {
        'prompt_tokens': 10,
        'completion_tokens': 5,
        'total_tokens': 15,
        'prompt_tokens_details': {'cached_tokens': 2, 'audio_tokens': 0},
      };

      final usage = GPTUsage.fromJson(json);
      final reconstructed = usage.toJson();

      expect(usage.promptTokens, 10);
      expect(usage.completionTokens, 5);
      expect(usage.totalTokens, 15);
      expect(usage.usageTokenDetails?.cachedTokens, 2);
      expect(reconstructed['prompt_tokens'], 10);
    });

    test('fromJson without usage token details', () {
      final json = {
        'prompt_tokens': 10,
        'completion_tokens': 5,
        'total_tokens': 15,
      };

      final usage = GPTUsage.fromJson(json);

      expect(usage.usageTokenDetails, null);
    });
  });

  group('GPTUsageTokenDetails', () {
    test('fromJson and toJson', () {
      final json = {'cached_tokens': 2, 'audio_tokens': 0};

      final details = GPTUsageTokenDetails.fromJson(json);
      final reconstructed = details.toJson();

      expect(details.cachedTokens, 2);
      expect(details.audioTokens, 0);
      expect(reconstructed['cached_tokens'], 2);
    });
  });

  group('GPTChunk', () {
    test('fromJson and toJson - streaming chunk', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion.chunk',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Hello'},
            'finish_reason': null,
          },
        ],
      };

      final chunk = GPTChunk.fromJson(json);
      final reconstructed = chunk.toJson();

      expect(chunk.id, 'chatcmpl-123');
      expect(chunk.model, 'gpt-4o');
      expect(chunk.done, false);
      expect(chunk.message?.content, 'Hello');
      expect(reconstructed['id'], 'chatcmpl-123');
    });

    test('fromJson - final chunk with finish_reason', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion.chunk',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'delta': {'content': '!'},
            'finish_reason': 'stop',
          },
        ],
      };

      final chunk = GPTChunk.fromJson(json);

      expect(chunk.done, true);
    });

    test('fromJson with tool calls', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion.chunk',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'delta': {
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'calculator', 'arguments': '{"a": 2'},
                  'index': 0,
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      };

      final chunk = GPTChunk.fromJson(json);

      expect(chunk.message?.toolCalls, isNotNull);
    });
  });

  group('GPTChunkChoice', () {
    test('fromJson and toJson', () {
      final json = {
        'index': 0,
        'delta': {'content': 'Hello'},
        'finish_reason': null,
      };

      final choice = GPTChunkChoice.fromJson(json);
      final reconstructed = choice.toJson();

      expect(choice.index, 0);
      expect(choice.delta.content, 'Hello');
      expect(reconstructed['index'], 0);
    });
  });

  group('GPTChunkChoiceDelta', () {
    test('fromJson and toJson with all fields', () {
      final json = {
        'role': 'assistant',
        'content': 'Hello',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'calculator', 'arguments': '{}'},
            'index': 0,
          },
        ],
      };

      final delta = GPTChunkChoiceDelta.fromJson(json);
      final reconstructed = delta.toJson();

      expect(delta.role, 'assistant');
      expect(delta.content, 'Hello');
      expect(delta.toolCalls?.length, 1);
      expect(reconstructed['role'], 'assistant');
      expect(reconstructed['content'], 'Hello');
    });

    test('toJson omits null fields', () {
      final delta = GPTChunkChoiceDelta(
        role: null,
        content: null,
        toolCalls: null,
      );

      final json = delta.toJson();

      expect(json.containsKey('role'), false);
      expect(json.containsKey('content'), false);
      expect(json.containsKey('tool_calls'), false);
    });
  });

  group('Extension methods', () {
    test('GPTToolCallToLLMToolCallExt.toLLMToolCalls', () {
      final gptToolCalls = [
        GPTToolCall(
          id: 'call_1',
          index: 0,
          type: 'function',
          function: GPTToolFunctionCall(
            name: 'calculator',
            arguments: '{"a": 2, "b": 2}',
          ),
        ),
        GPTToolCall(
          id: 'call_2',
          index: 1,
          type: 'function',
          function: GPTToolFunctionCall(name: 'search', arguments: '{}'),
        ),
      ];

      final llmToolCalls = gptToolCalls.toLLMToolCalls;

      // Should only take first tool call
      expect(llmToolCalls.length, 1);
      expect(llmToolCalls[0].id, 'call_1');
      expect(llmToolCalls[0].name, 'calculator');
      expect(llmToolCalls[0].arguments, '{"a": 2, "b": 2}');
    });

    test('GPTMessageToLLMMessageExt.toLLMMessage', () {
      final gptMessage = GPTMessage(
        role: 'assistant',
        content: 'Hello!',
        refusal: null,
        toolCalls: null,
      );

      final llmMessage = gptMessage.toLLMMessage;

      expect(llmMessage.role, LLMRole.assistant);
      expect(llmMessage.content, 'Hello!');
    });

    test('GPTMessageToLLMMessageExt.toLLMMessage with tool calls', () {
      final gptMessage = GPTMessage(
        role: 'assistant',
        content: null,
        refusal: null,
        toolCalls: [
          GPTToolCall(
            id: 'call_1',
            index: 0,
            type: 'function',
            function: GPTToolFunctionCall(name: 'calculator', arguments: '{}'),
          ),
        ],
      );

      final llmMessage = gptMessage.toLLMMessage;

      expect(llmMessage.toolCalls, isNotNull);
      expect(llmMessage.toolCalls?.length, 1);
    });
  });
}
