import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeVllmBaseUrl', () {
    test('accepts every common spelling of the same server', () {
      // A user handed the base URL as `http://host:8000/v1` — the form the
      // vLLM docs print — which naive concatenation turned into
      // `/v1/v1/chat/completions` and the server answered with a 404.
      const equivalent = [
        'http://192.168.0.74:8000',
        'http://192.168.0.74:8000/',
        'http://192.168.0.74:8000/v1',
        'http://192.168.0.74:8000/v1/',
        '  http://192.168.0.74:8000/v1  ',
      ];

      for (final baseUrl in equivalent) {
        expect(
          normalizeVllmBaseUrl(baseUrl),
          'http://192.168.0.74:8000',
          reason: 'failed for "$baseUrl"',
        );
      }
    });

    test('preserves a path prefix that is not the API version', () {
      // Reverse proxies commonly mount vLLM under a sub-path.
      expect(
        normalizeVllmBaseUrl('https://gateway.example.com/vllm'),
        'https://gateway.example.com/vllm',
      );
      expect(
        normalizeVllmBaseUrl('https://gateway.example.com/vllm/v1/'),
        'https://gateway.example.com/vllm',
      );
    });

    test('strips only one /v1 segment', () {
      // A literal `/v1/v1` prefix is not something we should silently "fix"
      // beyond the single version segment we know we append.
      expect(
        normalizeVllmBaseUrl('http://host:8000/v1/v1'),
        'http://host:8000/v1',
      );
    });
  });

  group('vllmEndpoint', () {
    test('builds one /v1 path regardless of base URL spelling', () {
      for (final baseUrl in [
        'http://192.168.0.74:8000',
        'http://192.168.0.74:8000/',
        'http://192.168.0.74:8000/v1',
        'http://192.168.0.74:8000/v1/',
      ]) {
        expect(
          vllmEndpoint(baseUrl, 'chat/completions').toString(),
          'http://192.168.0.74:8000/v1/chat/completions',
          reason: 'failed for "$baseUrl"',
        );
      }
    });

    test('covers every endpoint the package calls', () {
      const baseUrl = 'http://localhost:8000/v1';
      expect(
        vllmEndpoint(baseUrl, 'chat/completions').path,
        '/v1/chat/completions',
      );
      expect(vllmEndpoint(baseUrl, 'embeddings').path, '/v1/embeddings');
      expect(vllmEndpoint(baseUrl, 'models').path, '/v1/models');
    });

    test('tolerates a leading slash on the path', () {
      expect(
        vllmEndpoint('http://localhost:8000', '/models').path,
        '/v1/models',
      );
    });
  });
}
