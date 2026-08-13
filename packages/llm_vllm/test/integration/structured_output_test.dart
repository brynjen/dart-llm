/// Integration tests for structured output against a live vLLM server.
///
/// Covers the portable `responseFormat` path (`json_schema` / `json_object`)
/// and one vLLM-native `structured_outputs` case. `think: false` throughout:
/// with no `--reasoning-parser`, inline `<think>` output would be subject to
/// the same grammar constraint and corrupt the JSON.
library;

import 'dart:convert';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('VLLM Integration Tests - Structured Output', () {
    late VLLMChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    tearDown(() {
      repo.close();
    });

    test(
      'json schema output conforms to the schema',
      () async {
        final response = await repo
            .chatResponse(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Return the city Oslo and the number 2 as JSON.',
                ),
              ],
              options: const LLMChatOptions(
                think: false,
                responseFormat: JsonSchemaFormat(
                  name: 'CityCount',
                  schema: {
                    'type': 'object',
                    'properties': {
                      'city': {'type': 'string'},
                      'count': {'type': 'integer'},
                    },
                    'required': ['city', 'count'],
                    'additionalProperties': false,
                  },
                ),
              ),
            )
            .timeout(const Duration(seconds: 90));

        final decoded =
            jsonDecode(response.content ?? '') as Map<String, dynamic>;
        expect(decoded['city'], isA<String>());
        expect(decoded['count'], isA<int>());
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'json_object mode returns parseable JSON',
      () async {
        final response = await repo
            .chatResponse(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content:
                      'Return a JSON object with a single key "answer" '
                      'holding the number 4.',
                ),
              ],
              options: const LLMChatOptions(
                think: false,
                responseFormat: JsonFormat(),
              ),
            )
            .timeout(const Duration(seconds: 90));

        expect(
          () => jsonDecode(response.content ?? ''),
          returnsNormally,
          reason:
              'json_object mode must yield parseable JSON, got: '
              '${response.content}',
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'vLLM-native structured_outputs choice constrains the answer',
      () async {
        final response = await repo
            .chatResponse(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content:
                      'Is the sky blue on a clear day? '
                      'Answer positive or negative.',
                ),
              ],
              options: LLMChatOptions(
                think: false,
                backendOptions: const VLLMStructuredOutputs.choice([
                  'positive',
                  'negative',
                ]).toBackendOptions(),
              ),
            )
            .timeout(const Duration(seconds: 90));

        expect(response.content?.trim(), isIn(['positive', 'negative']));
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
