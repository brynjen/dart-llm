import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMRepository', () {
    test('models calls /v1/models and parses response', () async {
      late Uri requestUrl;
      late Map<String, String> requestHeaders;
      final repo = VLLMRepository(
        baseUrl: 'http://localhost:8000',
        apiKey: 'secret',
        httpClient: MockClient((request) async {
          requestUrl = request.url;
          requestHeaders = request.headers;
          return http.Response(
            json.encode({
              'object': 'list',
              'data': [
                {'id': 'model-a', 'object': 'model', 'owned_by': 'vllm'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final models = await repo.models();

      expect(requestUrl.path, '/v1/models');
      expect(requestHeaders['authorization'], 'Bearer secret');
      expect(models, hasLength(1));
      expect(models.single.id, 'model-a');
      expect(models.single.ownedBy, 'vllm');
    });

    test('models parses max_model_len', () async {
      final repo = VLLMRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient(
          (request) async => http.Response(
            json.encode({
              'object': 'list',
              'data': [
                {'id': 'model-a', 'object': 'model', 'max_model_len': 204800},
              ],
            }),
            200,
          ),
        ),
      );

      final models = await repo.models();
      expect(models.single.maxModelLen, 204800);
    });
  });

  group('VLLMRepository.describe', () {
    /// A fake deployment: chat probes succeed, embeddings probe fails (a
    /// chat-only server), openapi is served.
    MockClient chatServer() => MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/models') {
        return http.Response(
          json.encode({
            'object': 'list',
            'data': [
              {'id': 'chat-model', 'object': 'model', 'max_model_len': 204800},
            ],
          }),
          200,
        );
      }
      if (path == '/v1/chat/completions') {
        // Both the tool-calling and reasoning probes hit this endpoint and
        // read only the status code.
        return http.Response(json.encode({'choices': []}), 200);
      }
      if (path == '/v1/embeddings') {
        return http.Response(
          json.encode({
            'error': {'message': 'does not support embeddings'},
          }),
          400,
        );
      }
      if (path == '/openapi.json') {
        return http.Response(
          json.encode({
            'components': {
              'schemas': {
                'ChatCompletionRequest': {
                  'properties': {
                    'model': {},
                    'messages': {},
                    'temperature': {},
                    'brand_new_param': {},
                  },
                },
              },
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    test('aggregates models, capabilities, and params in one call', () async {
      final repo = VLLMRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: chatServer(),
      );

      final info = await repo.describe();

      expect(info.reachable, isTrue);
      expect(info.error, isNull);
      expect(info.baseUrl, 'http://localhost:8000');
      expect(info.models.single.id, 'chat-model');
      expect(info.models.single.maxModelLen, 204800);

      final capabilities = info.capabilities['chat-model'];
      expect(capabilities, isNotNull);
      expect(capabilities!.tools, isTrue);
      expect(capabilities.thinking, isTrue);
      expect(capabilities.embeddings, isFalse);
      expect(capabilities.structuredOutput, isTrue);

      expect(info.supportedParams, contains('brand_new_param'));
      expect(info.toString(), contains('chat-model'));
      expect(info.toString(), contains('204800'));
    });

    test('an unreachable server degrades instead of throwing', () async {
      final repo = VLLMRepository(
        baseUrl: 'http://localhost:9999',
        httpClient: MockClient(
          (_) async => throw http.ClientException('Connection refused'),
        ),
      );

      final info = await repo.describe();

      expect(info.reachable, isFalse);
      expect(info.error, contains('Connection refused'));
      expect(info.models, isEmpty);
      expect(info.capabilities, isEmpty);
      expect(info.supportedParams, isNull);
      expect(info.toString(), contains('unreachable'));
    });

    test('unreadable openapi leaves supportedParams null', () async {
      final repo = VLLMRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/v1/models') {
            return http.Response(
              json.encode({
                'object': 'list',
                'data': [
                  {'id': 'chat-model', 'object': 'model'},
                ],
              }),
              200,
            );
          }
          if (path == '/openapi.json') return http.Response('nope', 404);
          return http.Response(json.encode({'choices': []}), 200);
        }),
      );

      final info = await repo.describe();

      expect(info.reachable, isTrue);
      expect(info.supportedParams, isNull);
      expect(info.models.single.maxModelLen, isNull);
    });
  });
}
