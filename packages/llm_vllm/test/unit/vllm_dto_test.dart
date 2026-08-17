import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMChunk.fromJson', () {
    test('parses content chunk with usage', () {
      final json = {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': 'Hello'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      };

      final chunk = VLLMChunk.fromJson(json);

      expect(chunk.model, 'test-model');
      expect(
        chunk.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.role, LLMRole.assistant);
      expect(chunk.done, true);
      expect(chunk.promptEvalCount, 10);
      expect(chunk.evalCount, 5);
      expect(chunk.usage?.totalTokens, 15);
    });

    test('parses reasoning content aliases', () {
      final json = {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'delta': {
              'role': 'assistant',
              'reasoning_content': 'I should be brief',
            },
            'finish_reason': null,
          },
        ],
      };

      final chunk = VLLMChunk.fromJson(json);

      expect(chunk.message?.thinking, 'I should be brief');
      expect(chunk.done, false);
    });

    test('parses tool calls and synthesizes missing ids', () {
      final json = {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'delta': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'index': 0,
                  'type': 'function',
                  'function': {
                    'name': 'calculator',
                    'arguments': '{"a":2,"b":2}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      };

      final chunk = VLLMChunk.fromJson(json);

      expect(chunk.message?.toolCalls, hasLength(1));
      expect(chunk.message?.toolCalls?.first.id, 'tool_0_calculator');
      expect(chunk.message?.toolCalls?.first.name, 'calculator');
      expect(chunk.message?.toolCalls?.first.arguments, '{"a":2,"b":2}');
      expect(chunk.finishReason, LLMFinishReason.toolCalls);
    });

    test('parses usage-only chunk', () {
      final json = {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'test-model',
        'choices': <dynamic>[],
        'usage': {
          'prompt_tokens': 2,
          'completion_tokens': 3,
          'total_tokens': 5,
        },
      };

      final chunk = VLLMChunk.fromJson(json);

      expect(chunk.message, isNull);
      expect(chunk.done, true);
      expect(chunk.usage?.totalTokens, 5);
    });
  });

  group('VLLMModel.fromJson', () {
    test('parses OpenAI-compatible model object', () {
      final json = {
        'id': 'Qwen/Qwen3-0.6B',
        'object': 'model',
        'created': 1700000000,
        'owned_by': 'vllm',
        'root': 'Qwen/Qwen3-0.6B',
        'parent': null,
        'max_model_len': 204800,
      };

      final model = VLLMModel.fromJson(json);

      expect(model.id, 'Qwen/Qwen3-0.6B');
      expect(model.name, 'Qwen/Qwen3-0.6B');
      expect(model.created, 1700000000);
      expect(model.ownedBy, 'vllm');
      expect(model.maxModelLen, 204800);
      expect(model.toJson()['id'], 'Qwen/Qwen3-0.6B');
      expect(model.toJson()['max_model_len'], 204800);
    });

    test('maxModelLen is optional', () {
      final model = VLLMModel.fromJson({'id': 'm', 'object': 'model'});
      expect(model.maxModelLen, isNull);
      expect(model.toJson().containsKey('max_model_len'), isFalse);
    });

    test('parses model list response', () {
      final response = VLLMModelsResponse.fromJson({
        'object': 'list',
        'data': [
          {'id': 'model-a', 'object': 'model'},
          {'id': 'model-b', 'object': 'model'},
        ],
      });

      expect(response.data.map((model) => model.id), ['model-a', 'model-b']);
    });

    test('parses reasoning tokens from completion_tokens_details', () {
      final usage = VLLMUsage.fromJson(const {
        'prompt_tokens': 10,
        'completion_tokens': 30,
        'total_tokens': 40,
        'completion_tokens_details': {'reasoning_tokens': 20},
      });
      expect(usage.reasoningTokens, 20);

      final withoutDetails = VLLMUsage.fromJson(const {
        'prompt_tokens': 10,
        'completion_tokens': 30,
        'total_tokens': 40,
      });
      expect(withoutDetails.reasoningTokens, isNull);
    });
  });
}
