import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

const _model = 'gemini-3.5-flash-lite';

String _sseLine(Map<String, dynamic> data) => 'data: ${json.encode(data)}\n';

String _simpleResponse({String content = 'Hello!'}) =>
    _sseLine({
      'event_type': 'interaction.created',
      'interaction': {'id': 'int_1', 'model': _model, 'status': 'in_progress'},
    }) +
    _sseLine({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'text', 'text': content},
    }) +
    _sseLine({
      'event_type': 'interaction.completed',
      'interaction': {
        'id': 'int_1',
        'status': 'completed',
        'usage': {
          'total_tokens': 8,
          'total_input_tokens': 5,
          'total_output_tokens': 3,
        },
      },
    });

String _toolCallResponse() =>
    _sseLine({
      'event_type': 'interaction.created',
      'interaction': {'id': 'int_1', 'model': _model, 'status': 'in_progress'},
    }) +
    _sseLine({
      'event_type': 'step.start',
      'index': 0,
      'step': {
        'type': 'function_call',
        'id': 'call_abc123',
        'name': 'echo',
        'arguments': <String, dynamic>{},
      },
    }) +
    _sseLine({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'arguments_delta', 'arguments': '{"message":'},
    }) +
    _sseLine({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'arguments_delta', 'arguments': '"hi"}'},
    }) +
    _sseLine({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'thought_signature', 'signature': 'SIGX'},
    }) +
    _sseLine({
      'event_type': 'interaction.completed',
      'interaction': {'id': 'int_1', 'status': 'completed'},
    });

/// Runs one `streamChat` call against a mock client and returns the request.
Future<http.Request> _captureRequest(
  Future<void> Function(GeminiChatRepository repo) run, {
  String apiKey = 'key',
}) async {
  late http.Request captured;
  final client = MockClient((request) async {
    captured = request;
    return http.Response(
      _simpleResponse(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final repo = GeminiChatRepository(apiKey: apiKey, httpClient: client);
  await run(repo);
  return captured;
}

Future<Map<String, dynamic>> _captureBody(
  Future<void> Function(GeminiChatRepository repo) run,
) async {
  final request = await _captureRequest(run);
  return json.decode(request.body) as Map<String, dynamic>;
}

void main() {
  group('GeminiChatRepository', () {
    test('creates with default values', () {
      final repo = GeminiChatRepository(apiKey: 'test-key');
      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://generativelanguage.googleapis.com');
      expect(repo.maxToolAttempts, 90);
    });

    test('creates with custom configuration', () {
      final repo = GeminiChatRepository(
        apiKey: 'my-key',
        baseUrl: 'https://custom.example.com',
        maxToolAttempts: 5,
      );
      expect(repo.baseUrl, 'https://custom.example.com');
      expect(repo.maxToolAttempts, 5);
    });

    test('builder creates repository correctly', () {
      final repo = GeminiChatRepository.builder()
          .apiKey('builder-key')
          .baseUrl('https://api.example.com')
          .maxToolAttempts(3)
          .build();
      expect(repo.apiKey, 'builder-key');
      expect(repo.maxToolAttempts, 3);
    });

    test('builder throws when api key is missing', () {
      expect(() => GeminiChatRepository.builder().build(), throwsArgumentError);
    });

    test('validates model name', () {
      final repo = GeminiChatRepository(apiKey: 'key');
      expect(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        ),
        emitsError(isA<Exception>()),
      );
    });

    test('validates messages', () {
      final repo = GeminiChatRepository(apiKey: 'key');
      expect(
        repo.streamChat(_model, messages: []),
        emitsError(isA<Exception>()),
      );
    });

    test('posts to the /v1beta/interactions endpoint', () async {
      final request = await _captureRequest(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
            )
            .toList(),
      );

      expect(request.url.path, '/v1beta/interactions');
      expect(request.url.path, isNot(contains('generateContent')));
      expect(request.url.path, isNot(contains(_model)));
    });

    test('sends the api key as a header, never in the URL', () async {
      final request = await _captureRequest(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
            )
            .toList(),
        apiKey: 'my-gemini-key',
      );

      expect(request.headers['x-goog-api-key'], 'my-gemini-key');
      expect(request.url.queryParameters.containsKey('key'), isFalse);
      expect(request.url.query, isEmpty);
      expect(request.url.toString(), isNot(contains('my-gemini-key')));
    });

    test('sends model, stream and store:false', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
            )
            .toList(),
      );

      expect(body['model'], _model);
      expect(body['stream'], isTrue);
      // streamChat is stateless: it resends full history, so nothing is stored.
      expect(body['store'], isFalse);
      expect(body.containsKey('contents'), isFalse);
      expect(body.containsKey('systemInstruction'), isFalse);
    });

    test('serializes the conversation into typed input steps', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [
                LLMMessage(role: LLMRole.system, content: 'Be concise.'),
                LLMMessage(role: LLMRole.user, content: 'Hello'),
                LLMMessage(role: LLMRole.assistant, content: 'Hi there'),
                LLMMessage(role: LLMRole.user, content: 'More'),
              ],
            )
            .toList(),
      );

      final input = (body['input'] as List).cast<Map<String, dynamic>>();
      expect(input.map((step) => step['type']), [
        'user_input',
        'user_input',
        'model_output',
        'user_input',
      ]);
      expect((input.first['content'] as List).first, {
        'type': 'text',
        'text': 'Be concise.',
      });
    });

    test('sends tools as a flat array of function entries', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              tools: [_EchoTool()],
              options: const LLMChatOptions(autoExecuteTools: false),
            )
            .toList(),
      );

      final tools = (body['tools'] as List).cast<Map<String, dynamic>>();
      expect(tools.length, 1);
      expect(tools.first['type'], 'function');
      expect(tools.first['name'], 'echo');
      expect(tools.first['parameters'], isA<Map>());
      // Not nested under functionDeclarations like generateContent.
      expect(tools.first.containsKey('functionDeclarations'), isFalse);
    });

    test('sends thinking_summaries none by default', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['thinking_summaries'], 'none');
      expect(config.containsKey('thinking_level'), isFalse);
      expect(body.containsKey('generationConfig'), isFalse);
    });

    test('maps think and reasoningBudget onto thinking fields', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              think: true,
              options: const LLMChatOptions(
                think: true,
                reasoningBudget: 16384,
              ),
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['thinking_summaries'], 'auto');
      expect(config['thinking_level'], 'high');
      // A raw token budget is never sent; the field does not exist.
      expect(config.containsKey('thinkingConfig'), isFalse);
      expect(config.containsKey('thinking_budget'), isFalse);
    });

    test('thinkingLevelForBudget uses documented thresholds', () {
      expect(GeminiChatRepository.thinkingLevelForBudget(null), 'medium');
      expect(GeminiChatRepository.thinkingLevelForBudget(0), 'minimal');
      expect(GeminiChatRepository.thinkingLevelForBudget(512), 'low');
      expect(GeminiChatRepository.thinkingLevelForBudget(4096), 'medium');
      expect(GeminiChatRepository.thinkingLevelForBudget(32768), 'high');
    });

    test('reasoningEffort wins over budget for thinking_level', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              options: const LLMChatOptions(
                think: true,
                reasoningBudget: 16384, // would derive 'high'
                reasoningEffort: ReasoningEffort.low,
              ),
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['thinking_level'], 'low');
    });

    test('thinkingLevelForEffort clamps to the API subset', () {
      expect(
        GeminiChatRepository.thinkingLevelForEffort(ReasoningEffort.none),
        'minimal',
      );
      expect(
        GeminiChatRepository.thinkingLevelForEffort(ReasoningEffort.minimal),
        'minimal',
      );
      expect(
        GeminiChatRepository.thinkingLevelForEffort(ReasoningEffort.medium),
        'medium',
      );
      expect(
        GeminiChatRepository.thinkingLevelForEffort(ReasoningEffort.xhigh),
        'high',
      );
      expect(
        GeminiChatRepository.thinkingLevelForEffort(ReasoningEffort.max),
        'high',
      );
    });

    test('backendOptions thinking_level still wins over effort', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              options: const LLMChatOptions(
                think: true,
                reasoningEffort: ReasoningEffort.low,
                backendOptions: {'thinking_level': 'high'},
              ),
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['thinking_level'], 'high');
    });

    test('backendOptions thinking_level overrides the mapping', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              options: const LLMChatOptions(
                think: true,
                reasoningBudget: 100,
                backendOptions: {'thinking_level': 'high'},
              ),
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['thinking_level'], 'high');
      expect(body.containsKey('thinking_level'), isFalse);
    });

    test('maps generation options to snake_case fields', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              options: const LLMChatOptions(
                temperature: 0.4,
                maxOutputTokens: 256,
              ),
            )
            .toList(),
      );

      final config = body['generation_config'] as Map<String, dynamic>;
      expect(config['temperature'], 0.4);
      expect(config['max_output_tokens'], 256);
    });

    test('sends previous_interaction_id from backendOptions', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
              options: const LLMChatOptions(
                backendOptions: {'previous_interaction_id': 'int_prev'},
              ),
            )
            .toList(),
      );

      expect(body['previous_interaction_id'], 'int_prev');
    });

    test('JsonFormat sets a response_format array', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              options: const LLMChatOptions(responseFormat: JsonFormat()),
            )
            .toList(),
      );

      expect(body['response_format'], [
        {'type': 'object'},
      ]);
    });

    test('JsonSchemaFormat inlines the schema as the entry', () async {
      const schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      };
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              options: const LLMChatOptions(
                responseFormat: JsonSchemaFormat(
                  name: 'Answer',
                  schema: schema,
                ),
              ),
            )
            .toList(),
      );

      expect(body['response_format'], [
        {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
          },
        },
      ]);
    });

    test('no responseFormat omits response_format', () async {
      final body = await _captureBody(
        (repo) => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
      );

      expect(body.containsKey('response_format'), isFalse);
    });

    test('streams content from a successful response', () async {
      final client = MockClient((request) async {
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      final chunks = await repo
          .streamChat(
            _model,
            messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
          )
          .toList();

      expect(chunks, isNotEmpty);
      final content = chunks
          .where((c) => c.message?.content?.isNotEmpty == true)
          .map((c) => c.message!.content!)
          .join();
      expect(content, 'Hello!');
      expect(chunks.last.done, isTrue);
      expect(chunks.last.usage?.promptTokens, 5);
      expect(chunks.last.usage?.completionTokens, 3);
    });

    test('runs the tool loop and replays the call in the next turn', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(json.decode(request.body) as Map<String, dynamic>);
        final body = bodies.length == 1
            ? _toolCallResponse()
            : _simpleResponse(content: 'You said hi.');
        return http.Response(
          body,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      final chunks = await repo
          .streamChat(
            _model,
            messages: [LLMMessage(role: LLMRole.user, content: 'Echo hi')],
            tools: [_EchoTool()],
          )
          .toList();

      expect(bodies.length, 2);
      final secondInput = (bodies[1]['input'] as List)
          .cast<Map<String, dynamic>>();
      expect(secondInput.map((step) => step['type']), [
        'user_input',
        'thought',
        'function_call',
        'function_result',
      ]);
      // The thought signature captured from the stream is echoed back and
      // stripped from the ids.
      expect(secondInput[1]['signature'], 'SIGX');
      expect(secondInput[2], {
        'type': 'function_call',
        'id': 'call_abc123',
        'name': 'echo',
        'arguments': {'message': 'hi'},
      });
      expect(secondInput[3], {
        'type': 'function_result',
        'call_id': 'call_abc123',
        'name': 'echo',
        'result': [
          {'type': 'text', 'text': 'hi'},
        ],
      });

      expect(chunks.any((c) => c.message?.role == LLMRole.tool), isTrue);
      expect(chunks.last.done, isTrue);
      expect(chunks.last.finishReason, LLMFinishReason.stop);
    });

    test('throws LLMApiException on non-200 response', () async {
      final client = MockClient((request) async {
        return http.Response(
          json.encode({
            'error': {'code': 401, 'message': 'API key not valid.'},
          }),
          401,
        );
      });

      final repo = GeminiChatRepository(apiKey: 'bad-key', httpClient: client);
      expect(
        () => repo
            .streamChat(
              _model,
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('embed uses the api key header on embedContent', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          json.encode({
            'embedding': {
              'values': [0.1, 0.2, 0.3],
            },
          }),
          200,
        );
      });

      final repo = GeminiChatRepository(
        apiKey: 'embed-key',
        httpClient: client,
      );
      final embeddings = await repo.embed(
        model: 'gemini-embedding-001',
        messages: ['hello'],
      );

      expect(captured.headers['x-goog-api-key'], 'embed-key');
      expect(captured.url.queryParameters.containsKey('key'), isFalse);
      expect(captured.url.path, endsWith(':embedContent'));
      expect(embeddings.length, 1);
      expect(embeddings.first.embedding, [0.1, 0.2, 0.3]);
      expect(embeddings.first.model, 'gemini-embedding-001');
    });

    test('batchEmbed uses the api key header on batchEmbedContents', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          json.encode({
            'embeddings': [
              {
                'values': [0.1, 0.2],
              },
              {
                'values': [0.3, 0.4],
              },
            ],
          }),
          200,
        );
      });

      final repo = GeminiChatRepository(
        apiKey: 'embed-key',
        httpClient: client,
      );
      final embeddings = await repo.batchEmbed(
        model: 'gemini-embedding-001',
        messages: ['hello', 'world'],
      );

      expect(captured.headers['x-goog-api-key'], 'embed-key');
      expect(captured.url.queryParameters.containsKey('key'), isFalse);
      expect(captured.url.path, endsWith(':batchEmbedContents'));
      expect(embeddings.length, 2);
      expect(embeddings[0].embedding, [0.1, 0.2]);
      expect(embeddings[1].embedding, [0.3, 0.4]);
    });
  });
}

class _EchoTool extends LLMTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'Echoes the input back';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'message',
      type: 'string',
      description: 'Message to echo',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      args['message'];
}
