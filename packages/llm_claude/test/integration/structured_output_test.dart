/// Integration tests for structured JSON output.
library;

import 'dart:convert';

import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Claude Integration Tests - Structured Output', () {
    late ClaudeChatRepository repo;

    setUp(() {
      if (!hasApiKey()) return;
      repo = createRepository();
    });

    test(
      'json schema output',
      () async {
        if (!hasApiKey()) {
          markTestSkipped('API key not available');
          return;
        }

        final response = await repo
            .chatResponse(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Return Oslo and the number 2 as JSON.',
                ),
              ],
              options: const LLMChatOptions(
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

        final decoded = jsonDecode(_jsonOnly(response.content ?? ''));
        expect(decoded['city'], isA<String>());
        expect(decoded['count'], isA<int>());
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

String _jsonOnly(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  return trimmed
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
}
