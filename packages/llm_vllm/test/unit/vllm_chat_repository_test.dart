import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMChatRepository', () {
    test('creates with default values', () {
      final repo = VLLMChatRepository();
      expect(repo.baseUrl, 'http://localhost:8000');
      expect(repo.apiKey, isNull);
      expect(repo.maxToolAttempts, 90);
    });

    test('creates with custom configuration', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );

      final repo = VLLMChatRepository(
        baseUrl: 'http://custom:8000',
        apiKey: 'secret',
        maxToolAttempts: 10,
        retryConfig: retryConfig,
        timeoutConfig: timeoutConfig,
      );

      expect(repo.baseUrl, 'http://custom:8000');
      expect(repo.apiKey, 'secret');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder creates repository correctly', () {
      final repo = VLLMChatRepositoryBuilder()
          .baseUrl('http://test:8000')
          .apiKey('secret')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .build();

      expect(repo.baseUrl, 'http://test:8000');
      expect(repo.apiKey, 'secret');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
    });
  });

  group('VLLMChatRepository request mapping', () {
    test(
      'sends OpenAI-compatible chat request without auth by default',
      () async {
        final client = _QueueStreamClient([_contentResponse('ok')]);
        final repo = VLLMChatRepository(
          baseUrl: 'http://localhost:8000',
          httpClient: client,
        );

        await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            )
            .toList();

        expect(client.requests.single.path, '/v1/chat/completions');
        expect(
          client.requestHeaders.single.containsKey('authorization'),
          false,
        );
        expect(client.requestBodies.single['model'], 'test-model');
        expect(client.requestBodies.single['stream'], true);
        expect(client.requestBodies.single['stream_options'], {
          'include_usage': true,
        });
        expect(client.requestBodies.single['messages'], isA<List<dynamic>>());
      },
    );

    test('sends authorization header when apiKey is configured', () async {
      final client = _QueueStreamClient([_contentResponse('ok')]);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        apiKey: 'secret',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
          )
          .toList();

      expect(client.requestHeaders.single['authorization'], 'Bearer secret');
    });

    test(
      'maps shared options and backendOptions to top-level fields',
      () async {
        final client = _QueueStreamClient([_contentResponse('ok')]);
        final repo = VLLMChatRepository(
          baseUrl: 'http://localhost:8000',
          httpClient: client,
        );

        await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
              options: const StreamChatOptions(
                think: true,
                temperature: 0.2,
                topP: 0.8,
                topK: 40,
                maxOutputTokens: 32,
                stopSequences: ['END'],
                backendOptions: {
                  'repetition_penalty': 1.05,
                  // `extra_body` is a Python-SDK wrapper, not a wire field —
                  // vLLM ignores it, so its contents must be flattened.
                  'extra_body': {'min_p': 0.05},
                },
              ),
            )
            .toList();

        final body = client.requestBodies.single;
        expect(body['temperature'], 0.2);
        expect(body['top_p'], 0.8);
        expect(body['top_k'], 40);
        expect(body['max_completion_tokens'], 32);
        expect(body['stop'], ['END']);
        // Thinking is gated by the chat template. vLLM's `include_reasoning`
        // exists but defaults to true and only controls whether reasoning is
        // *surfaced*, so it is the wrong knob and is not sent.
        expect(body['chat_template_kwargs'], {'enable_thinking': true});
        expect(body.containsKey('include_reasoning'), isFalse);
        expect(body['repetition_penalty'], 1.05);
        expect(body['min_p'], 0.05);
        expect(body.containsKey('extra_body'), isFalse);
      },
    );

    test('sends enable_thinking:false so think:false is honored', () async {
      final client = _QueueStreamClient([_contentResponse('ok')]);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'Qwen/Qwen3-0.6B',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            options: const StreamChatOptions(think: false),
          )
          .toList();

      // Qwen3 thinks by default, so omitting the flag would leave think:false
      // unhonored.
      expect(client.requestBodies.single['chat_template_kwargs'], {
        'enable_thinking': false,
      });
    });

    test('rejects unknown and obsolete backendOptions keys', () async {
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: _QueueStreamClient([_contentResponse('ok')]),
      );

      // The server ignores these silently and returns unconstrained output,
      // so the library fails loudly instead.
      for (final options in [
        const StreamChatOptions(
          backendOptions: {
            'guided_choice': ['a', 'b'],
          },
        ),
        const StreamChatOptions(
          backendOptions: {
            'extra_body': {'guided_regex': r'\d+'},
          },
        ),
        // vLLM drops unknown fields silently, so a typo must fail loudly here.
        const StreamChatOptions(backendOptions: {'repitition_penalty': 1.1}),
      ]) {
        expect(
          () => repo
              .streamChat(
                'test-model',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
                options: options,
              )
              .toList(),
          throwsArgumentError,
        );
      }
    });

    test('maps tool_choice shorthands to the OpenAI object form', () async {
      final cases = <String, Object>{
        'auto': 'auto',
        'none': 'none',
        'required': 'required',
        'calculator': {
          'type': 'function',
          'function': {'name': 'calculator'},
        },
      };
      for (final entry in cases.entries) {
        final client = _QueueStreamClient([_contentResponse('ok')]);
        final repo = VLLMChatRepository(
          baseUrl: 'http://localhost:8000',
          httpClient: client,
        );
        await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              tools: [CalculatorTool()],
              options: StreamChatOptions(
                autoExecuteTools: false,
                backendOptions: {'tool_choice': entry.key},
              ),
            )
            .toList();
        expect(
          client.requestBodies.single['tool_choice'],
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('sends vLLM-native structured_outputs at the top level', () async {
      final client = _QueueStreamClient([_contentResponse('positive')]);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'I love it')],
            options: StreamChatOptions(
              backendOptions: const VLLMStructuredOutputs.choice([
                'positive',
                'negative',
              ]).toBackendOptions(),
            ),
          )
          .toList();

      expect(client.requestBodies.single['structured_outputs'], {
        'choice': ['positive', 'negative'],
      });
    });

    test('responseFormat takes precedence over backendOptions', () async {
      final client = _QueueStreamClient([_contentResponse('ok')]);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            options: const StreamChatOptions(
              backendOptions: {
                'response_format': {'type': 'text'},
              },
              responseFormat: JsonFormat(),
            ),
          )
          .toList();

      expect(client.requestBodies.single['response_format'], {
        'type': 'json_object',
      });
    });
  });

  group('VLLMChatRepository tool loop behavior', () {
    test(
      'autoExecuteTools false exposes tool calls without executing tools',
      () async {
        final client = _QueueStreamClient([_toolCallResponse()]);
        final repo = VLLMChatRepository(
          baseUrl: 'http://localhost:8000',
          httpClient: client,
        );

        final chunks = await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: '2+2?')],
              tools: [CalculatorTool()],
              options: const StreamChatOptions(autoExecuteTools: false),
            )
            .toList();

        expect(client.sendCount, 1);
        expect(
          chunks.any((c) => (c.message?.toolCalls ?? const []).isNotEmpty),
          isTrue,
        );
        expect(chunks.any((c) => c.message?.role == LLMRole.tool), isFalse);
      },
    );

    test(
      'autoExecuteTools true executes tools and continues chat loop',
      () async {
        final client = _QueueStreamClient([
          _toolCallResponse(),
          _contentResponse('4'),
        ]);
        final repo = VLLMChatRepository(
          baseUrl: 'http://localhost:8000',
          httpClient: client,
        );

        final chunks = await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: '2+2?')],
              tools: [CalculatorTool()],
            )
            .toList();

        expect(client.sendCount, 2);
        expect(chunks.any((c) => c.message?.role == LLMRole.tool), isTrue);
      },
    );
  });

  group('VLLMChatRepository validation', () {
    test('validates model name', () async {
      final repo = VLLMChatRepository();

      await expectLater(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('validates messages', () async {
      final repo = VLLMChatRepository();

      await expectLater(
        repo.streamChat('test-model', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });
  });
}

class _QueueStreamClient extends http.BaseClient {
  _QueueStreamClient(this._responses);

  final List<http.StreamedResponse> _responses;
  final List<Uri> requests = [];
  final List<Map<String, String>> requestHeaders = [];
  final List<Map<String, dynamic>> requestBodies = [];
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    requestHeaders.add(Map<String, String>.from(request.headers));
    final bodyBytes = await request.finalize().toBytes();
    if (bodyBytes.isNotEmpty) {
      requestBodies.add(
        json.decode(utf8.decode(bodyBytes)) as Map<String, dynamic>,
      );
    } else {
      requestBodies.add(const <String, dynamic>{});
    }

    if (sendCount >= _responses.length) {
      throw StateError('No queued response for request #$sendCount');
    }
    final response = _responses[sendCount];
    sendCount += 1;
    return response;
  }
}

class CalculatorTool extends LLMTool {
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
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return '4';
  }
}

http.StreamedResponse _contentResponse(String content) {
  return _sseResponse([
    {
      'id': 'chatcmpl-test',
      'created': 1700000000,
      'model': 'test-model',
      'choices': [
        {
          'index': 0,
          'delta': {'role': 'assistant', 'content': content},
          'finish_reason': null,
        },
      ],
    },
    {
      'id': 'chatcmpl-test',
      'created': 1700000000,
      'model': 'test-model',
      'choices': [
        {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
      ],
      'usage': {'prompt_tokens': 3, 'completion_tokens': 1, 'total_tokens': 4},
    },
  ]);
}

http.StreamedResponse _toolCallResponse() {
  return _sseResponse([
    {
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
                'id': 'call_1',
                'index': 0,
                'type': 'function',
                'function': {
                  'name': 'calculator',
                  'arguments': '{"expression":"2+2"}',
                },
              },
            ],
          },
          'finish_reason': null,
        },
      ],
    },
    {
      'id': 'chatcmpl-test',
      'created': 1700000000,
      'model': 'test-model',
      'choices': [
        {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'},
      ],
    },
  ]);
}

http.StreamedResponse _sseResponse(List<Map<String, dynamic>> frames) {
  final buffer = StringBuffer();
  for (final frame in frames) {
    buffer.writeln('data: ${json.encode(frame)}');
    buffer.writeln();
  }
  buffer.writeln('data: [DONE]');
  buffer.writeln();
  return http.StreamedResponse(
    Stream.value(utf8.encode(buffer.toString())),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}
