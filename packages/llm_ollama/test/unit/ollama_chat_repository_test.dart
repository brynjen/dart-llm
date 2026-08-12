import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaChatRepository', () {
    test('creates with default values', () {
      final repo = OllamaChatRepository();
      expect(repo.baseUrl, 'http://localhost:11434');
      expect(repo.maxToolAttempts, 90);
    });

    test('creates with custom configuration', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );

      final repo = OllamaChatRepository(
        baseUrl: 'http://custom:8080',
        maxToolAttempts: 10,
        retryConfig: retryConfig,
        timeoutConfig: timeoutConfig,
      );

      expect(repo.baseUrl, 'http://custom:8080');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder creates repository correctly', () {
      final repo = OllamaChatRepositoryBuilder()
          .baseUrl('http://test:8080')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .build();

      expect(repo.baseUrl, 'http://test:8080');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
    });
  });

  group('OllamaChatRepository validation', () {
    test('validates model name', () async {
      final repo = OllamaChatRepository();

      // Validation happens when the stream is listened to
      await expectLater(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('validates messages', () async {
      final repo = OllamaChatRepository();

      await expectLater(
        repo.streamChat('test-model', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });
  });

  group('OllamaChatRepository tool loop behavior', () {
    test(
      'autoExecuteTools false exposes tool calls without executing tools',
      () async {
        final client = _QueueStreamClient([
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:00.000Z',
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {
                    'name': 'calculator',
                    'arguments': {'expression': '2 + 2'},
                  },
                },
              ],
            },
            'done': true,
          }),
        ]);
        final repo = OllamaChatRepository(
          baseUrl: 'http://localhost:11434',
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
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:00.000Z',
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {
                    'name': 'calculator',
                    'arguments': {'expression': '2 + 2'},
                  },
                },
              ],
            },
            'done': true,
          }),
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:01.000Z',
            'message': {'role': 'assistant', 'content': '4'},
            'done': true,
          }),
        ]);
        final repo = OllamaChatRepository(
          baseUrl: 'http://localhost:11434',
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

    test('JsonFormat sets format to "json" string', () async {
      final client = _QueueStreamClient([
        _streamResponse({
          'model': 'test-model',
          'created_at': '2024-01-01T00:00:00.000Z',
          'message': {'role': 'assistant', 'content': 'ok'},
          'done': true,
        }),
      ]);
      final repo = OllamaChatRepository(
        baseUrl: 'http://localhost:11434',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            options: const StreamChatOptions(responseFormat: JsonFormat()),
          )
          .toList();

      expect(client.requestBodies.single['format'], 'json');
    });

    test('JsonSchemaFormat sets format to schema object', () async {
      final schema = {'type': 'object', 'properties': {}};
      final client = _QueueStreamClient([
        _streamResponse({
          'model': 'test-model',
          'created_at': '2024-01-01T00:00:00.000Z',
          'message': {'role': 'assistant', 'content': 'ok'},
          'done': true,
        }),
      ]);
      final repo = OllamaChatRepository(
        baseUrl: 'http://localhost:11434',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            options: StreamChatOptions(
              responseFormat: JsonSchemaFormat(name: 'Result', schema: schema),
            ),
          )
          .toList();

      expect(client.requestBodies.single['format'], schema);
    });

    test(
      'responseFormat takes precedence over backendOptions format',
      () async {
        final client = _QueueStreamClient([
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:00.000Z',
            'message': {'role': 'assistant', 'content': 'ok'},
            'done': true,
          }),
        ]);
        final repo = OllamaChatRepository(
          baseUrl: 'http://localhost:11434',
          httpClient: client,
        );

        await repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
              options: const StreamChatOptions(
                responseFormat: JsonFormat(),
                backendOptions: {'format': 'should-be-ignored'},
              ),
            )
            .toList();

        expect(client.requestBodies.single['format'], 'json');
      },
    );

    test('null responseFormat does not emit format key', () async {
      final client = _QueueStreamClient([
        _streamResponse({
          'model': 'test-model',
          'created_at': '2024-01-01T00:00:00.000Z',
          'message': {'role': 'assistant', 'content': 'ok'},
          'done': true,
        }),
      ]);
      final repo = OllamaChatRepository(
        baseUrl: 'http://localhost:11434',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
          )
          .toList();

      expect(client.requestBodies.single.containsKey('format'), isFalse);
    });

    test('backendOptions are mapped to Ollama request body', () async {
      final client = _QueueStreamClient([
        _streamResponse({
          'model': 'test-model',
          'created_at': '2024-01-01T00:00:00.000Z',
          'message': {'role': 'assistant', 'content': 'ok'},
          'done': true,
        }),
      ]);
      final repo = OllamaChatRepository(
        baseUrl: 'http://localhost:11434',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hello')],
            options: const StreamChatOptions(
              backendOptions: {
                'format': 'json',
                'options': {'temperature': 0},
                'keepAlive': '5m',
              },
            ),
          )
          .toList();

      final requestBody = client.requestBodies.single;
      expect(requestBody['format'], 'json');
      expect(requestBody['options'], {'temperature': 0});
      expect(requestBody['keep_alive'], '5m');
      expect(requestBody.containsKey('keepAlive'), isFalse);
    });

    test(
      'strict mode throws when tool attempts are exhausted before final assistant answer',
      () async {
        final client = _QueueStreamClient([
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:00.000Z',
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {
                    'name': 'calculator',
                    'arguments': {'expression': '2 + 2'},
                  },
                },
              ],
            },
            'done': true,
          }),
          _streamResponse({
            'model': 'test-model',
            'created_at': '2024-01-01T00:00:01.000Z',
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_2',
                  'function': {
                    'name': 'calculator',
                    'arguments': {'expression': '3 + 3'},
                  },
                },
              ],
            },
            'done': true,
          }),
        ]);
        final repo = OllamaChatRepository(
          baseUrl: 'http://localhost:11434',
          httpClient: client,
        );

        await expectLater(
          repo
              .streamChat(
                'test-model',
                messages: [LLMMessage(role: LLMRole.user, content: '2+2?')],
                tools: [CalculatorTool()],
                toolAttempts: 1,
                options: const StreamChatOptions(),
              )
              .toList(),
          throwsA(isA<ToolLoopIncompleteException>()),
        );
        expect(client.sendCount, 2);
      },
    );
  });
}

class _QueueStreamClient extends http.BaseClient {
  _QueueStreamClient(this._responses);

  final List<http.StreamedResponse> _responses;
  final List<Map<String, dynamic>> requestBodies = [];
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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

http.StreamedResponse _streamResponse(Map<String, dynamic> frame) {
  return http.StreamedResponse(
    Stream.value(utf8.encode('${json.encode(frame)}\n')),
    200,
  );
}
