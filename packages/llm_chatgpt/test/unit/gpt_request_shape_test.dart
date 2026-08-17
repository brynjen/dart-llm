/// Wire-shape tests for the OpenAI `/v1/chat/completions` request body.
///
/// These assert the exact JSON sent per model family. They exist because the
/// failures they guard against are **400 errors from the live API** — there
/// is no OpenAI key in CI, so the request shape is verified here rather than
/// by an integration test.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

/// Streams one request against a canned response and returns the JSON body
/// that was sent.
Future<Map<String, dynamic>> capture(
  String model, {
  LLMChatOptions? options,
}) async {
  final client = _StreamCapturingClient();
  final repo = ChatGPTChatRepository(apiKey: 'k', httpClient: client);
  await repo
      .streamChat(
        model,
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: options,
      )
      .toList();
  return client.bodies.single;
}

void main() {
  group('sampling parameters', () {
    test('reasoning models never get temperature/top_p', () async {
      for (final model in ['gpt-5', 'o3-mini', 'gpt-5.1']) {
        final body = await capture(
          model,
          options: const LLMChatOptions(temperature: 0.4, topP: 0.9),
        );
        expect(body.containsKey('temperature'), isFalse, reason: model);
        expect(body.containsKey('top_p'), isFalse, reason: model);
      }
    });

    test('conventional models keep temperature/top_p', () async {
      final body = await capture(
        'gpt-4o',
        options: const LLMChatOptions(temperature: 0.4, topP: 0.9),
      );
      expect(body['temperature'], 0.4);
      expect(body['top_p'], 0.9);
    });
  });

  group('reasoning_effort', () {
    test('effort maps to the clamped wire value', () async {
      final body = await capture(
        'gpt-5',
        options: const LLMChatOptions(reasoningEffort: ReasoningEffort.max),
      );
      expect(body['reasoning_effort'], 'high');
    });

    test('effort wins over budget (effort-native backend)', () async {
      final body = await capture(
        'gpt-5',
        options: const LLMChatOptions(
          reasoningEffort: ReasoningEffort.low,
          reasoningBudget: 60000,
        ),
      );
      expect(body['reasoning_effort'], 'low');
    });

    test('budget alone derives an effort level (no hardcoded low)', () async {
      // Regression: any reasoningBudget used to send reasoning_effort: 'low'.
      final expectations = <int, String>{
        1024: 'low',
        4096: 'medium',
        16384: 'high',
        60000: 'high', // max clamps to gpt-5's ceiling
      };
      for (final entry in expectations.entries) {
        final body = await capture(
          'gpt-5',
          options: LLMChatOptions(reasoningBudget: entry.key),
        );
        expect(body['reasoning_effort'], entry.value, reason: '${entry.key}');
      }
    });

    test(
      'knobs apply regardless of think (reasoning models always reason)',
      () async {
        final body = await capture(
          'gpt-5',
          options: const LLMChatOptions(
            think: false,
            reasoningEffort: ReasoningEffort.high,
          ),
        );
        expect(body['reasoning_effort'], 'high');
      },
    );

    test('nothing is sent with no knobs set', () async {
      final body = await capture(
        'gpt-5',
        options: const LLMChatOptions(think: true),
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('never sent to conventional models (hard 400 there)', () async {
      final body = await capture(
        'gpt-4o',
        options: const LLMChatOptions(
          reasoningEffort: ReasoningEffort.high,
          reasoningBudget: 4096,
        ),
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('never sent to o1-mini (predates the parameter)', () async {
      final body = await capture(
        'o1-mini',
        options: const LLMChatOptions(reasoningEffort: ReasoningEffort.high),
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test(
      'backendOptions reasoning_effort overrides the derived value',
      () async {
        final body = await capture(
          'gpt-5',
          options: const LLMChatOptions(
            reasoningEffort: ReasoningEffort.low,
            backendOptions: {'reasoning_effort': 'high'},
          ),
        );
        expect(body['reasoning_effort'], 'high');
      },
    );
  });

  group('stream_options', () {
    test('include_usage is requested', () async {
      final body = await capture('gpt-4o');
      expect(body['stream_options'], {'include_usage': true});
    });

    test('backendOptions can override stream_options', () async {
      final body = await capture(
        'gpt-4o',
        options: const LLMChatOptions(
          backendOptions: {
            'stream_options': {'include_usage': false},
          },
        ),
      );
      expect(body['stream_options'], {'include_usage': false});
    });
  });

  group('streamed DTOs', () {
    test('usage-only final frame does not crash and carries usage', () async {
      final client = _StreamCapturingClient();
      final repo = ChatGPTChatRepository(apiKey: 'k', httpClient: client);
      final chunks = await repo
          .streamChat(
            'gpt-5',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();
      final usage = chunks.lastWhere((c) => c.usage != null).usage!;
      expect(usage.promptTokens, 10);
      expect(usage.completionTokens, 30);
      expect(usage.reasoningTokens, 20);
    });

    test('reasoning deltas surface as thinking', () async {
      final client = _StreamCapturingClient();
      final repo = ChatGPTChatRepository(apiKey: 'k', httpClient: client);
      final chunks = await repo
          .streamChat(
            'gpt-5',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();
      final thinking = chunks
          .map((c) => c.message?.thinking)
          .whereType<String>()
          .join();
      expect(thinking, 'because');
    });

    test('GPTChunk tolerates an empty choices list', () {
      final chunk = GPTChunk.fromJson({
        'id': 'x',
        'created': 1700000000,
        'model': 'gpt-5',
        'choices': <dynamic>[],
        'usage': {
          'prompt_tokens': 1,
          'completion_tokens': 2,
          'total_tokens': 3,
        },
      });
      expect(chunk.message, isNull);
      expect(chunk.done, isTrue);
      expect(chunk.usage!.totalTokens, 3);
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
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'gpt-5',
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'reasoning_content': 'because'},
            'finish_reason': null,
          },
        ],
      },
      {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'gpt-5',
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'ok'},
            'finish_reason': null,
          },
        ],
      },
      {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'gpt-5',
        'choices': [
          {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
        ],
      },
      // Usage-only frame sent when stream_options.include_usage is on.
      {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'gpt-5',
        'choices': <dynamic>[],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 30,
          'total_tokens': 40,
          'completion_tokens_details': {'reasoning_tokens': 20},
        },
      },
    ];
    final sse = StringBuffer();
    for (final frame in frames) {
      sse.writeln('data: ${json.encode(frame)}');
      sse.writeln();
    }
    sse.writeln('data: [DONE]');
    return http.StreamedResponse(
      Stream.value(utf8.encode(sse.toString())),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}
