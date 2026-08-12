import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

String _sseEvent(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${json.encode(data)}\n\n';

String _simpleResponse({String content = 'Hello!'}) =>
    _sseEvent('message_start', {
      'message': {
        'model': 'claude-opus-4-6',
        'usage': {'input_tokens': 10},
      },
    }) +
    _sseEvent('content_block_start', {
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }) +
    _sseEvent('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': content},
    }) +
    _sseEvent('content_block_stop', {'index': 0}) +
    _sseEvent('message_delta', {
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 5},
    }) +
    _sseEvent('message_stop', {});

void main() {
  group('ClaudeChatRepository', () {
    test('creates with default values', () {
      final repo = ClaudeChatRepository(apiKey: 'test-key');
      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://api.anthropic.com');
      expect(repo.maxToolAttempts, 90);
    });

    test('creates with custom configuration', () {
      final repo = ClaudeChatRepository(
        apiKey: 'my-key',
        baseUrl: 'https://custom.example.com',
        maxToolAttempts: 5,
      );
      expect(repo.baseUrl, 'https://custom.example.com');
      expect(repo.maxToolAttempts, 5);
    });

    test('builder creates repository correctly', () {
      final repo = ClaudeChatRepository.builder()
          .apiKey('builder-key')
          .baseUrl('https://api.example.com')
          .maxToolAttempts(3)
          .build();
      expect(repo.apiKey, 'builder-key');
      expect(repo.baseUrl, 'https://api.example.com');
      expect(repo.maxToolAttempts, 3);
    });

    test('builder throws when api key is missing', () {
      expect(() => ClaudeChatRepository.builder().build(), throwsArgumentError);
    });

    test('validates model name', () {
      final repo = ClaudeChatRepository(apiKey: 'key');
      expect(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        ),
        emitsError(isA<Exception>()),
      );
    });

    test('validates messages', () {
      final repo = ClaudeChatRepository(apiKey: 'key');
      expect(
        repo.streamChat('claude-opus-4-6', messages: []),
        emitsError(isA<Exception>()),
      );
    });

    test('streams content from successful response', () async {
      final client = MockClient((request) async {
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
      final chunks = await repo
          .streamChat(
            'claude-opus-4-6',
            messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
          )
          .toList();

      expect(chunks, isNotEmpty);
      final content = chunks
          .where((c) => c.message?.content?.isNotEmpty == true)
          .map((c) => c.message!.content!)
          .join();
      expect(content, 'Hello!');
    });

    test('throws LLMApiException on non-200 response', () async {
      final client = MockClient((request) async {
        return http.Response(
          json.encode({
            'type': 'error',
            'error': {
              'type': 'invalid_request_error',
              'message': 'Bad request',
            },
          }),
          400,
        );
      });

      final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
      expect(
        () => repo
            .streamChat(
              'claude-opus-4-6',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('embed throws UnsupportedError', () async {
      final repo = ClaudeChatRepository(apiKey: 'key');
      expect(
        () => repo.embed(model: 'claude-opus-4-6', messages: ['hello']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('batchEmbed throws UnsupportedError', () async {
      final repo = ClaudeChatRepository(apiKey: 'key');
      expect(
        () => repo.batchEmbed(model: 'claude-opus-4-6', messages: ['hello']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('sends x-api-key and anthropic-version headers', () async {
      late http.BaseRequest capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = ClaudeChatRepository(
        apiKey: 'test-api-key',
        httpClient: client,
      );
      await repo
          .streamChat(
            'claude-opus-4-6',
            messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
          )
          .toList();

      expect(capturedRequest.headers['x-api-key'], 'test-api-key');
      expect(capturedRequest.headers['anthropic-version'], '2023-06-01');
    });

    test('includes system message as top-level field', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'claude-opus-4-6',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'Be helpful.'),
              LLMMessage(role: LLMRole.user, content: 'Hello'),
            ],
          )
          .toList();

      expect(capturedBody['system'], 'Be helpful.');
      // System message should not appear in the messages array
      final msgs = capturedBody['messages'] as List;
      expect(msgs.every((m) => m['role'] != 'system'), isTrue);
    });
  });

  group('ClaudeChatRepository responseFormat', () {
    final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];

    test(
      'JsonFormat injects JSON-only instruction into system field',
      () async {
        late Map<String, dynamic> capturedBody;
        final client = MockClient((request) async {
          capturedBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            _simpleResponse(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });

        final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
        await repo
            .streamChat(
              'claude-opus-4-6',
              messages: messages,
              options: const StreamChatOptions(responseFormat: JsonFormat()),
            )
            .toList();

        final system = capturedBody['system'] as String;
        expect(system, contains('valid JSON'));
      },
    );

    test(
      'JsonSchemaFormat uses native output_config on supporting models',
      () async {
        late Map<String, dynamic> capturedBody;
        final client = MockClient((request) async {
          capturedBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            _simpleResponse(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });

        final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
        await repo
            .streamChat(
              'claude-opus-4-6',
              messages: messages,
              options: const StreamChatOptions(
                responseFormat: JsonSchemaFormat(
                  name: 'MyOutput',
                  schema: {'type': 'object'},
                ),
              ),
            )
            .toList();

        // Opus 4.6 supports native structured outputs, so the schema must
        // constrain decoding via output_config rather than being pasted into
        // the system prompt as an instruction the model may ignore.
        final format = (capturedBody['output_config'] as Map)['format'] as Map;
        expect(format['type'], 'json_schema');
        expect(format['schema'], {'type': 'object'});
        expect(capturedBody['system'], isNull);
      },
    );

    test('JsonFormat appended after existing system message', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'claude-opus-4-6',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'Be concise.'),
              ...messages,
            ],
            options: const StreamChatOptions(responseFormat: JsonFormat()),
          )
          .toList();

      final system = capturedBody['system'] as String;
      expect(system, startsWith('Be concise.'));
      expect(system, contains('valid JSON'));
    });

    test('null responseFormat does not inject system field', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = ClaudeChatRepository(apiKey: 'key', httpClient: client);
      await repo.streamChat('claude-opus-4-6', messages: messages).toList();

      expect(capturedBody.containsKey('system'), isFalse);
    });
  });
}
