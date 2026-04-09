import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

String _sseLine(Map<String, dynamic> data) => 'data: ${json.encode(data)}\n';

String _simpleResponse({String content = 'Hello!'}) =>
    _sseLine({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': content},
            ],
          },
        },
      ],
    }) +
    _sseLine({
      'candidates': [
        {
          'content': {'role': 'model', 'parts': []},
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': {'promptTokenCount': 5, 'candidatesTokenCount': 3},
    });

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
        repo.streamChat('gemini-2.0-flash', messages: []),
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

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      final chunks = await repo
          .streamChat(
            'gemini-2.0-flash',
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
            'error': {'code': 401, 'message': 'API key not valid.'},
          }),
          401,
        );
      });

      final repo = GeminiChatRepository(apiKey: 'bad-key', httpClient: client);
      expect(
        () => repo
            .streamChat(
              'gemini-2.0-flash',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('puts api key in URL query param', () async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = GeminiChatRepository(
        apiKey: 'my-gemini-key',
        httpClient: client,
      );
      await repo
          .streamChat(
            'gemini-2.0-flash',
            messages: [LLMMessage(role: LLMRole.user, content: 'Hi')],
          )
          .toList();

      expect(capturedUri.queryParameters['key'], 'my-gemini-key');
      expect(capturedUri.path, contains('gemini-2.0-flash'));
      expect(capturedUri.path, contains('streamGenerateContent'));
    });

    test('includes systemInstruction when system message present', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'gemini-2.0-flash',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'Be concise.'),
              LLMMessage(role: LLMRole.user, content: 'Hello'),
            ],
          )
          .toList();

      expect(capturedBody['systemInstruction'], isNotNull);
      final parts = capturedBody['systemInstruction']['parts'] as List;
      expect(parts.first['text'], 'Be concise.');
      // System message should not appear in contents
      final contents = capturedBody['contents'] as List;
      expect(contents.every((c) => c['role'] != 'system'), isTrue);
    });

    test('embed returns LLMEmbedding list', () async {
      final client = MockClient((request) async {
        return http.Response(
          json.encode({
            'embedding': {
              'values': [0.1, 0.2, 0.3],
            },
          }),
          200,
        );
      });

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      final embeddings = await repo.embed(
        model: 'text-embedding-004',
        messages: ['hello'],
      );

      expect(embeddings.length, 1);
      expect(embeddings.first.embedding, [0.1, 0.2, 0.3]);
      expect(embeddings.first.model, 'text-embedding-004');
    });

    test('batchEmbed returns multiple LLMEmbedding entries', () async {
      final client = MockClient((request) async {
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

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      final embeddings = await repo.batchEmbed(
        model: 'text-embedding-004',
        messages: ['hello', 'world'],
      );

      expect(embeddings.length, 2);
      expect(embeddings[0].embedding, [0.1, 0.2]);
      expect(embeddings[1].embedding, [0.3, 0.4]);
    });

    test('JsonFormat sets generationConfig.responseMimeType to application/json',
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

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'gemini-2.0-flash',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            options: const StreamChatOptions(responseFormat: JsonFormat()),
          )
          .toList();

      final gc = capturedBody['generationConfig'] as Map<String, dynamic>;
      expect(gc['responseMimeType'], 'application/json');
      expect(gc.containsKey('responseSchema'), isFalse);
    });

    test(
        'JsonSchemaFormat sets responseMimeType and responseSchema in generationConfig',
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

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'gemini-2.0-flash',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            options: const StreamChatOptions(
              responseFormat: JsonSchemaFormat(
                name: 'Answer',
                schema: {'type': 'OBJECT', 'properties': {}},
              ),
            ),
          )
          .toList();

      final gc = capturedBody['generationConfig'] as Map<String, dynamic>;
      expect(gc['responseMimeType'], 'application/json');
      expect(gc['responseSchema'], {'type': 'OBJECT', 'properties': {}});
    });

    test('null responseFormat does not emit generationConfig', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _simpleResponse(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final repo = GeminiChatRepository(apiKey: 'key', httpClient: client);
      await repo
          .streamChat(
            'gemini-2.0-flash',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();

      expect(capturedBody.containsKey('generationConfig'), isFalse);
    });
  });
}
