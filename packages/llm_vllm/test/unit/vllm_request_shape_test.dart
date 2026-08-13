/// Wire-shape tests for the vLLM `/v1/chat/completions` request body.
///
/// These pin the exact JSON sent for the parameter-handling paths that have
/// silently failed before: alias normalization, `tool_choice` extraction,
/// and the `chat_template_kwargs` merge. vLLM drops unknown fields with a
/// `200`, so a wrong body here is invisible at runtime — the wire shape has
/// to be verified where it is built.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

/// Streams one request against a canned response and returns the JSON body
/// that was sent.
Future<Map<String, dynamic>> capture({
  List<LLMTool> tools = const [],
  LLMChatOptions? options,
}) async {
  final client = _StreamCapturingClient();
  final repo = VLLMChatRepository(httpClient: client);
  await repo
      .streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        tools: tools,
        options: options,
      )
      .toList();
  return client.bodies.single;
}

void main() {
  group('backendOptions normalization', () {
    test('camelCase aliases reach the wire in snake_case', () async {
      final body = await capture(
        options: const LLMChatOptions(
          backendOptions: {'topP': 0.9, 'repetitionPenalty': 1.05},
        ),
      );
      expect(body['top_p'], 0.9);
      expect(body['repetition_penalty'], 1.05);
      expect(body.containsKey('topP'), isFalse);
      expect(body.containsKey('repetitionPenalty'), isFalse);
    });

    test('toolChoice alias is applied, not silently dropped', () async {
      // Regression: `toolChoice` passed validation (the alias is declared)
      // but was read from the raw map by wire name, so it never reached the
      // request body.
      final body = await capture(
        tools: [_CalculatorTool()],
        options: const LLMChatOptions(
          autoExecuteTools: false,
          backendOptions: {'toolChoice': 'auto'},
        ),
      );
      expect(body['tool_choice'], 'auto');
    });

    test('toolChoice alias still gets named-function wrapping', () async {
      final body = await capture(
        tools: [_CalculatorTool()],
        options: const LLMChatOptions(
          autoExecuteTools: false,
          backendOptions: {'toolChoice': 'calculator'},
        ),
      );
      expect(body['tool_choice'], {
        'type': 'function',
        'function': {'name': 'calculator'},
      });
    });

    test('tool_choice nested in extra_body is applied', () async {
      final body = await capture(
        tools: [_CalculatorTool()],
        options: const LLMChatOptions(
          autoExecuteTools: false,
          backendOptions: {
            'extra_body': {'tool_choice': 'none'},
          },
        ),
      );
      expect(body['tool_choice'], 'none');
    });

    test('backendOptions scalars win over typed generation options', () async {
      final body = await capture(
        options: const LLMChatOptions(
          temperature: 0.2,
          backendOptions: {'temperature': 0.9},
        ),
      );
      expect(body['temperature'], 0.9);
    });
  });

  group('tool_choice without tools', () {
    test('"none" and "auto" pass through', () async {
      for (final mode in ['none', 'auto']) {
        final body = await capture(
          options: LLMChatOptions(backendOptions: {'tool_choice': mode}),
        );
        expect(body['tool_choice'], mode, reason: mode);
        expect(body.containsKey('tools'), isFalse, reason: mode);
      }
    });

    test('"required" and a named tool are rejected client-side', () async {
      // vLLM answers 400 on these; the client-side error names the actual
      // problem instead of a server error about a request nobody meant.
      for (final choice in ['required', 'calculator']) {
        await expectLater(
          capture(
            options: LLMChatOptions(backendOptions: {'tool_choice': choice}),
          ),
          throwsArgumentError,
          reason: choice,
        );
      }
    });
  });

  group('chat_template_kwargs', () {
    test(
      'caller kwargs merge with enable_thinking instead of clobbering it',
      () async {
        // Regression: a wholesale assignment discarded enable_thinking — and
        // with it the `think:` flag — whenever unrelated kwargs were set.
        final body = await capture(
          options: const LLMChatOptions(
            think: true,
            backendOptions: {
              'chat_template_kwargs': {'custom_flag': 1},
            },
          ),
        );
        expect(body['chat_template_kwargs'], {
          'custom_flag': 1,
          'enable_thinking': true,
        });
      },
    );

    test('explicit enable_thinking in kwargs overrides think:', () async {
      final body = await capture(
        options: const LLMChatOptions(
          think: true,
          backendOptions: {
            'chat_template_kwargs': {'enable_thinking': false},
          },
        ),
      );
      expect(body['chat_template_kwargs'], {'enable_thinking': false});
    });

    test('chatTemplateKwargs alias merges the same way', () async {
      final body = await capture(
        options: const LLMChatOptions(
          think: false,
          backendOptions: {
            'chatTemplateKwargs': {'custom_flag': 1},
          },
        ),
      );
      expect(body['chat_template_kwargs'], {
        'custom_flag': 1,
        'enable_thinking': false,
      });
    });
  });

  group('multiple candidates', () {
    test('n = 1 is accepted', () async {
      final body = await capture(
        options: const LLMChatOptions(backendOptions: {'n': 1}),
      );
      expect(body['n'], 1);
    });

    test('n > 1 is rejected: the stream surfaces only choices[0]', () async {
      await expectLater(
        capture(options: const LLMChatOptions(backendOptions: {'n': 3})),
        throwsArgumentError,
      );
    });
  });

  group('messages', () {
    test('consecutive system messages are merged into one', () async {
      final client = _StreamCapturingClient();
      final repo = VLLMChatRepository(httpClient: client);
      await repo
          .streamChat(
            'test-model',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'You are terse.'),
              LLMMessage(role: LLMRole.system, content: 'Answer in Norwegian.'),
              LLMMessage(role: LLMRole.user, content: 'hi'),
            ],
          )
          .toList();

      final messages = client.bodies.single['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(
        (messages.first as Map<String, dynamic>)['content'],
        'You are terse.\n\nAnswer in Norwegian.',
      );
    });
  });

  group('response_format', () {
    test('JsonSchemaFormat produces the full json_schema envelope', () async {
      final body = await capture(
        options: const LLMChatOptions(
          responseFormat: JsonSchemaFormat(
            name: 'answer',
            schema: {
              'type': 'object',
              'properties': {
                'value': {'type': 'integer'},
              },
            },
          ),
        ),
      );
      expect(body['response_format'], {
        'type': 'json_schema',
        'json_schema': {
          'name': 'answer',
          'strict': true,
          'schema': {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
          },
        },
      });
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
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': 'ok'},
            'finish_reason': null,
          },
        ],
      },
      {
        'id': 'chatcmpl-test',
        'created': 1700000000,
        'model': 'test-model',
        'choices': [
          {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
        ],
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

class _CalculatorTool extends LLMTool {
  @override
  String get name => 'calculator';

  @override
  String get description => 'Calculates arithmetic expressions.';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'expression',
      type: 'string',
      description: 'Arithmetic expression to evaluate.',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      '4';
}
