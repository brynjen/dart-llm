/// Wire-shape tests for the Ollama `/api/chat` request body.
///
/// These pin the `think` field's bool-vs-level behavior: Ollama accepts a
/// bool or a level string ("low"/"medium"/"high"/"max"), some models take
/// either while gpt-oss ignores bools, and a wrong value is only an error on
/// a live server — so the wire shape is verified where it is built.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

/// Streams one request against a canned response and returns the JSON body
/// that was sent.
Future<Map<String, dynamic>> capture({LLMChatOptions? options}) async {
  final client = _StreamCapturingClient();
  final repo = OllamaChatRepository(httpClient: client);
  await repo
      .streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: options,
      )
      .toList();
  return client.bodies.single;
}

void main() {
  group('think', () {
    test('bare think:true stays a bool for bool-only models', () async {
      final body = await capture(options: const LLMChatOptions(think: true));
      expect(body['think'], true);
    });

    test('think:false is a bool', () async {
      final body = await capture(options: const LLMChatOptions(think: false));
      expect(body['think'], false);
    });

    test('effort maps to a level string with clamping', () async {
      final expectations = <ReasoningEffort, Object>{
        ReasoningEffort.none: false,
        ReasoningEffort.minimal: 'low',
        ReasoningEffort.low: 'low',
        ReasoningEffort.medium: 'medium',
        ReasoningEffort.high: 'high',
        ReasoningEffort.xhigh: 'high',
        ReasoningEffort.max: 'max',
      };
      for (final entry in expectations.entries) {
        final body = await capture(
          options: LLMChatOptions(think: true, reasoningEffort: entry.key),
        );
        expect(body['think'], entry.value, reason: '${entry.key}');
      }
    });

    test(
      'budget maps through the canonical bands (no native budget)',
      () async {
        final expectations = <int, Object>{
          0: false,
          256: 'low', // minimal band clamps to 'low' on the wire
          1024: 'low',
          4096: 'medium',
          16384: 'high',
          32768: 'high', // xhigh band clamps to 'high'
          60000: 'max',
        };
        for (final entry in expectations.entries) {
          final body = await capture(
            options: LLMChatOptions(think: true, reasoningBudget: entry.key),
          );
          expect(body['think'], entry.value, reason: '${entry.key}');
        }
      },
    );

    test('effort wins over budget (effort-native backend)', () async {
      final body = await capture(
        options: const LLMChatOptions(
          think: true,
          reasoningBudget: 60000,
          reasoningEffort: ReasoningEffort.low,
        ),
      );
      expect(body['think'], 'low');
    });

    test('knobs are ignored when think is false', () async {
      final body = await capture(
        options: const LLMChatOptions(
          reasoningEffort: ReasoningEffort.high,
          reasoningBudget: 4096,
        ),
      );
      expect(body['think'], false);
    });

    test('backendOptions think overrides everything', () async {
      final body = await capture(
        options: const LLMChatOptions(
          think: true,
          reasoningEffort: ReasoningEffort.low,
          backendOptions: {'think': 'max'},
        ),
      );
      expect(body['think'], 'max');
    });
  });
}

class _StreamCapturingClient extends http.BaseClient {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    bodies.add(json.decode(utf8.decode(bytes)) as Map<String, dynamic>);
    final frames = [
      {
        'model': 'test-model',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {'role': 'assistant', 'content': 'ok'},
        'done': false,
      },
      {
        'model': 'test-model',
        'created_at': '2024-01-01T00:00:00.100Z',
        'message': {'role': 'assistant', 'content': ''},
        'done': true,
      },
    ];
    final ndjson = frames.map(json.encode).join('\n');
    return http.StreamedResponse(
      Stream.value(utf8.encode('$ndjson\n')),
      200,
      headers: {'content-type': 'application/x-ndjson'},
    );
  }
}
