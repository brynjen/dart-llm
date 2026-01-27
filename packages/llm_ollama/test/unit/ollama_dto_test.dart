import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaChunk.fromJson', () {
    test('complete chunk with all fields', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {'role': 'assistant', 'content': 'Hello'},
        'done': true,
        'prompt_eval_count': 10,
        'eval_count': 5,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.model, 'qwen3:0.6b');
      expect(chunk.createdAt, DateTime.parse('2024-01-01T00:00:00.000Z'));
      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.role, LLMRole.assistant);
      expect(chunk.done, true);
      expect(chunk.promptEvalCount, 10);
      expect(chunk.evalCount, 5);
    });

    test('chunk without message', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'done': false,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message, null);
      expect(chunk.done, false);
    });

    test('chunk with thinking content', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {
          'role': 'assistant',
          'content': 'Hello',
          'thinking': 'I should greet the user',
        },
        'done': false,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.thinking, 'I should greet the user');
    });

    test('chunk with tool calls', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {
          'role': 'assistant',
          'tool_calls': [
            {
              'function': {
                'name': 'calculator',
                'arguments': '{"a": 2, "b": 2}',
              },
            },
          ],
        },
        'done': true,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message?.toolCalls, isNotNull);
      expect(chunk.message?.toolCalls?.length, 1);
      expect(chunk.message?.toolCalls?.first.name, 'calculator');
      expect(chunk.message?.toolCalls?.first.arguments, '{"a": 2, "b": 2}');
    });

    test('chunk with thinking embedded in content', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {
          'role': 'assistant',
          'content': 'Hello<think>I should greet</think>',
        },
        'done': false,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.thinking, 'I should greet');
    });

    test('chunk with multiline thinking in content', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {
          'role': 'assistant',
          'content': 'Hello<think>I should\ngreet the user\npolitely</think>',
        },
        'done': false,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message?.content, 'Hello');
      expect(chunk.message?.thinking, 'I should\ngreet the user\npolitely');
    });

    test('invalid role handling', () {
      final json = {
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {'role': 'invalid_role', 'content': 'Hello'},
        'done': false,
      };

      final chunk = OllamaChunk.fromJson(json);

      expect(chunk.message?.role, null);
      expect(chunk.message?.content, 'Hello');
    });
  });

  group('OllamaModel.fromJson', () {
    test('complete model data', () {
      final json = {
        'name': 'qwen3:0.6b',
        'model': 'qwen3:0.6b',
        'modified_at': '2024-01-01T00:00:00.000Z',
        'size': 1000000,
        'digest': 'sha256:abc123',
        'details': {
          'parent_model': 'qwen3',
          'format': 'gguf',
          'family': 'qwen',
          'families': ['qwen'],
          'parameter_size': '0.6B',
          'quantization_level': 'Q4_0',
        },
      };

      final model = OllamaModel.fromJson(json);

      expect(model.name, 'qwen3:0.6b');
      expect(model.model, 'qwen3:0.6b');
      expect(model.modifiedAt, DateTime.parse('2024-01-01T00:00:00.000Z'));
      expect(model.size, 1000000);
      expect(model.digest, 'sha256:abc123');
      expect(model.details.parentModel, 'qwen3');
      expect(model.details.format, 'gguf');
    });
  });

  group('OllamaModelDetails.fromJson', () {
    test('with missing optional fields', () {
      final json = {
        'format': 'gguf',
        'family': 'qwen',
        'parameter_size': '0.6B',
        'quantization_level': 'Q4_0',
      };

      final details = OllamaModelDetails.fromJson(json);

      expect(details.parentModel, '');
      expect(details.families, isEmpty);
      expect(details.format, 'gguf');
    });
  });

  group('OllamaModelInfo.fromJson', () {
    test('complete model info', () {
      final json = {
        'modelfile': 'FROM qwen3',
        'parameters': 'temperature 0.7',
        'template': '{{ .Prompt }}',
        'details': {
          'format': 'gguf',
          'family': 'qwen',
          'parameter_size': '0.6B',
          'quantization_level': 'Q4_0',
        },
        'model_info': {'key': 'value'},
      };

      final info = OllamaModelInfo.fromJson(json);

      expect(info.modelfile, 'FROM qwen3');
      expect(info.parameters, 'temperature 0.7');
      expect(info.template, '{{ .Prompt }}');
      expect(info.modelInfo, {'key': 'value'});
    });

    test('with missing optional fields', () {
      final json = {
        'details': {
          'format': 'gguf',
          'family': 'qwen',
          'parameter_size': '0.6B',
          'quantization_level': 'Q4_0',
        },
      };

      final info = OllamaModelInfo.fromJson(json);

      expect(info.modelfile, '');
      expect(info.parameters, '');
      expect(info.template, '');
      expect(info.modelInfo, null);
    });
  });

  group('OllamaVersion.fromJson', () {
    test('version parsing', () {
      final json = {'version': '1.2.3'};

      final version = OllamaVersion.fromJson(json);

      expect(version.version, '1.2.3');
    });
  });

  group('OllamaPullProgress', () {
    test('fromJson with normal progress', () {
      final json = {
        'status': 'pulling',
        'digest': 'sha256:abc123',
        'total': 1000,
        'completed': 500,
      };

      final progress = OllamaPullProgress.fromJson(json);

      expect(progress.status, 'pulling');
      expect(progress.digest, 'sha256:abc123');
      expect(progress.total, 1000);
      expect(progress.completed, 500);
      expect(progress.progress, 0.5);
    });

    test('progress getter with zero total', () {
      final json = {'status': 'pulling', 'total': 0, 'completed': 0};

      final progress = OllamaPullProgress.fromJson(json);

      expect(progress.progress, 0.0);
    });

    test('progress getter with null values', () {
      final json = {'status': 'pulling'};

      final progress = OllamaPullProgress.fromJson(json);

      expect(progress.total, null);
      expect(progress.completed, null);
      expect(progress.progress, 0.0);
    });

    test('progress getter with 100% progress', () {
      final json = {'status': 'complete', 'total': 1000, 'completed': 1000};

      final progress = OllamaPullProgress.fromJson(json);

      expect(progress.progress, 1.0);
    });

    test('toString includes progress percentage', () {
      final progress = OllamaPullProgress(
        status: 'pulling',
        total: 1000,
        completed: 750,
      );

      final str = progress.toString();
      expect(str, contains('75.0%'));
      expect(str, contains('pulling'));
    });
  });
}
