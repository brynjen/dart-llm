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
  });
}
