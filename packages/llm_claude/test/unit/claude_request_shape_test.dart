/// Wire-shape tests for the Anthropic Messages API.
///
/// These assert the exact JSON body sent for each model family. They exist
/// because the failures they guard against are **400 errors from the live
/// API** — there is no Anthropic key in CI, so the request shape is verified
/// here rather than by an integration test.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

String _sseEvent(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${json.encode(data)}\n\n';

String _simpleResponse() =>
    _sseEvent('message_start', {
      'message': {
        'model': 'claude-opus-5',
        'usage': {'input_tokens': 10},
      },
    }) +
    _sseEvent('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'hi'},
    }) +
    _sseEvent('message_delta', {
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 5},
    }) +
    _sseEvent('message_stop', {});

/// Streams a request and returns the JSON body that was sent.
Future<Map<String, dynamic>> capture(
  String model, {
  LLMChatOptions? options,
}) async {
  final client = _StreamCapturingClient();
  final repo = ClaudeChatRepository(apiKey: 'k', httpClient: client);
  await repo
      .streamChat(
        model,
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: options,
      )
      .toList();
  return client.bodies.single;
}

class _StreamCapturingClient extends http.BaseClient {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    bodies.add(json.decode(utf8.decode(bytes)) as Map<String, dynamic>);
    return http.StreamedResponse(
      Stream.value(utf8.encode(_simpleResponse())),
      200,
    );
  }
}

void main() {
  group('thinking', () {
    test('modern models get adaptive thinking, never budget_tokens', () async {
      // `thinking: {type: "enabled", budget_tokens: N}` is a 400 on these.
      for (final model in [
        'claude-opus-5',
        'claude-sonnet-5',
        'claude-opus-4-7',
      ]) {
        final body = await capture(
          model,
          options: const LLMChatOptions(think: true),
        );
        expect(body['thinking'], {
          'type': 'adaptive',
          'display': 'summarized',
        }, reason: '$model must use adaptive thinking');
      }
    });

    test('display is summarized so thinking text is not empty', () async {
      // The API default is "omitted", which returns thinking blocks whose text
      // is empty — chunk.message.thinking would always be blank.
      final body = await capture(
        'claude-opus-5',
        options: const LLMChatOptions(think: true),
      );
      expect((body['thinking'] as Map)['display'], 'summarized');
    });

    test('legacy models still get budget_tokens', () async {
      final body = await capture(
        'claude-haiku-4-5',
        options: const LLMChatOptions(think: true),
      );
      expect((body['thinking'] as Map)['type'], 'enabled');
      expect((body['thinking'] as Map)['budget_tokens'], isA<int>());
    });

    test('legacy budget never exceeds max_tokens', () async {
      // The old default paired a 10000-token budget with a 4096-token
      // max_tokens, which the API rejects outright: budget_tokens must be
      // strictly less than max_tokens.
      final body = await capture(
        'claude-haiku-4-5',
        options: const LLMChatOptions(think: true, reasoningBudget: 999999),
      );
      final maxTokens = body['max_tokens'] as int;
      final budget = (body['thinking'] as Map)['budget_tokens'] as int;
      expect(budget, lessThan(maxTokens));
    });

    test('reasoningBudget maps to effort on modern models', () async {
      final body = await capture(
        'claude-opus-5',
        options: const LLMChatOptions(think: true, reasoningBudget: 30000),
      );
      expect((body['output_config'] as Map)['effort'], 'max');
      expect(body['thinking'], isNot(contains('budget_tokens')));
    });

    test('no thinking field when think is false', () async {
      final body = await capture('claude-opus-5');
      expect(body.containsKey('thinking'), isFalse);
    });
  });

  group('sampling parameters', () {
    test('are omitted on modern models', () async {
      // temperature / top_p / top_k are rejected with a 400 on Opus 4.7+,
      // Sonnet 5, Fable 5 and Mythos 5.
      final body = await capture(
        'claude-opus-5',
        options: const LLMChatOptions(temperature: 0.5, topP: 0.9, topK: 40),
      );
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
      expect(body.containsKey('top_k'), isFalse);
    });

    test('are sent on models that accept them', () async {
      final body = await capture(
        'claude-haiku-4-5',
        options: const LLMChatOptions(temperature: 0.5, topP: 0.9, topK: 40),
      );
      expect(body['temperature'], 0.5);
      expect(body['top_p'], 0.9);
      expect(body['top_k'], 40);
    });

    test('stop_sequences and max_tokens are sent on every model', () async {
      for (final model in ['claude-opus-5', 'claude-haiku-4-5']) {
        final body = await capture(
          model,
          options: const LLMChatOptions(
            maxOutputTokens: 128,
            stopSequences: ['END'],
          ),
        );
        expect(body['max_tokens'], 128, reason: model);
        expect(body['stop_sequences'], ['END'], reason: model);
      }
    });
  });

  group('structured output', () {
    test('modern models use native output_config.format', () async {
      final body = await capture(
        'claude-opus-5',
        options: const LLMChatOptions(
          responseFormat: JsonSchemaFormat(
            name: 'person',
            schema: {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          ),
        ),
      );
      final format = (body['output_config'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      expect((format['schema'] as Map)['type'], 'object');
      // The schema must constrain decoding, not be pasted into the prompt.
      expect(body['system'], isNull);
    });

    test('legacy models fall back to system-prompt injection', () async {
      final body = await capture(
        'claude-haiku-4-5',
        options: const LLMChatOptions(
          responseFormat: JsonSchemaFormat(name: 'person', schema: {}),
        ),
      );
      expect(body.containsKey('output_config'), isFalse);
      expect(body['system'], contains('JSON Schema'));
    });
  });

  group('tool_choice', () {
    test('shorthand strings convert to the Messages API object form', () async {
      final cases = {
        'auto': {'type': 'auto'},
        'required': {'type': 'any'},
        'none': {'type': 'none'},
        'get_weather': {'type': 'tool', 'name': 'get_weather'},
      };
      for (final entry in cases.entries) {
        final body = await capture(
          'claude-opus-5',
          options: LLMChatOptions(
            tools: [_NoopTool()],
            backendOptions: {'tool_choice': entry.key},
          ),
        );
        expect(body['tool_choice'], entry.value, reason: entry.key);
      }
    });
  });

  group('headers', () {
    test('sends x-api-key and anthropic-version', () async {
      final client = _HeaderCapturingClient();
      final repo = ClaudeChatRepository(apiKey: 'secret', httpClient: client);
      await repo
          .streamChat(
            'claude-opus-5',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();
      expect(client.headers['x-api-key'], 'secret');
      expect(client.headers['anthropic-version'], '2023-06-01');
    });
  });
}

class _HeaderCapturingClient extends http.BaseClient {
  Map<String, String> headers = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers = request.headers;
    await request.finalize().toBytes();
    return http.StreamedResponse(
      Stream.value(utf8.encode(_simpleResponse())),
      200,
    );
  }
}

class _NoopTool extends LLMTool {
  @override
  String get name => 'get_weather';
  @override
  String get description => 'Get weather';
  @override
  List<LLMToolParam> get parameters => const [];
  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      'sunny';
}
