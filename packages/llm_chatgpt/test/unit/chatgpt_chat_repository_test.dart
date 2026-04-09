import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

// Minimal SSE payload that the GPT stream converter can decode.
String _sseChunk(String content) =>
    'data: ${json.encode({
          "id": "chatcmpl-test",
          "object": "chat.completion.chunk",
          "model": "gpt-4o",
          "choices": [
            {
              "index": 0,
              "delta": {"content": content},
              "finish_reason": null,
            },
          ],
        })}\n\n'
    'data: ${json.encode({
          "id": "chatcmpl-test",
          "object": "chat.completion.chunk",
          "model": "gpt-4o",
          "choices": [
            {
              "index": 0,
              "delta": {},
              "finish_reason": "stop",
            },
          ],
        })}\n\n'
    'data: [DONE]\n\n';

MockClient _captureClient(void Function(Map<String, dynamic>) onBody) =>
    MockClient((request) async {
      onBody(json.decode(request.body) as Map<String, dynamic>);
      return http.Response(
        _sseChunk('ok'),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

void main() {
  group('ChatGPTChatRepository', () {
    test('creates with required apiKey', () {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');
      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://api.openai.com');
      expect(repo.maxToolAttempts, 90);
    });

    test('creates with custom configuration', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
        readTimeout: Duration(minutes: 3),
      );

      final repo = ChatGPTChatRepository(
        apiKey: 'test-key',
        baseUrl: 'https://custom.openai.com',
        maxToolAttempts: 10,
        retryConfig: retryConfig,
        timeoutConfig: timeoutConfig,
      );

      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder creates repository correctly', () {
      final repo = ChatGPTChatRepositoryBuilder()
          .apiKey('test-key')
          .baseUrl('https://custom.openai.com')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .build();

      expect(repo.apiKey, 'test-key');
      expect(repo.baseUrl, 'https://custom.openai.com');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
    });

    test('builder requires apiKey', () {
      expect(
        () => ChatGPTChatRepositoryBuilder().build(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ChatGPTChatRepository responseFormat', () {
    final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];

    test('JsonFormat emits response_format json_object', () async {
      late Map<String, dynamic> body;
      final repo = ChatGPTChatRepository(
        apiKey: 'key',
        httpClient: _captureClient((b) => body = b),
      );
      await repo
          .streamChat(
            'gpt-4o',
            messages: messages,
            options: const StreamChatOptions(responseFormat: JsonFormat()),
          )
          .toList();

      expect(body['response_format'], {'type': 'json_object'});
    });

    test('JsonSchemaFormat emits response_format json_schema with name/schema/strict',
        () async {
      late Map<String, dynamic> body;
      final repo = ChatGPTChatRepository(
        apiKey: 'key',
        httpClient: _captureClient((b) => body = b),
      );
      await repo
          .streamChat(
            'gpt-4o',
            messages: messages,
            options: const StreamChatOptions(
              responseFormat: JsonSchemaFormat(
                name: 'Answer',
                schema: {'type': 'object', 'properties': {}},
                strict: false,
              ),
            ),
          )
          .toList();

      final rf = body['response_format'] as Map<String, dynamic>;
      expect(rf['type'], 'json_schema');
      final js = rf['json_schema'] as Map<String, dynamic>;
      expect(js['name'], 'Answer');
      expect(js['strict'], false);
      expect(js['schema'], {'type': 'object', 'properties': {}});
    });

    test('null responseFormat emits no response_format key', () async {
      late Map<String, dynamic> body;
      final repo = ChatGPTChatRepository(
        apiKey: 'key',
        httpClient: _captureClient((b) => body = b),
      );
      await repo
          .streamChat('gpt-4o', messages: messages)
          .toList();

      expect(body.containsKey('response_format'), isFalse);
    });
  });

  group('ChatGPTChatRepository validation', () {
    test('validates model name', () async {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');

      await expectLater(
        repo.streamChat(
          '',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        ),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('validates messages', () async {
      final repo = ChatGPTChatRepository(apiKey: 'test-key');

      await expectLater(
        repo.streamChat('test-model', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });
  });
}
