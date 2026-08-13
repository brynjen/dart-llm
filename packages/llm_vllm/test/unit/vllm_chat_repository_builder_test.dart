import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMChatRepositoryBuilder', () {
    test('all builder methods', () {
      final httpClient = http.Client();
      const retryConfig = RetryConfig(maxAttempts: 5);
      const timeoutConfig = TimeoutConfig(
        connectionTimeout: Duration(seconds: 5),
      );

      final repo = VLLMChatRepositoryBuilder()
          .baseUrl('http://custom:8000')
          .apiKey('secret')
          .maxToolAttempts(10)
          .retryConfig(retryConfig)
          .timeoutConfig(timeoutConfig)
          .httpClient(httpClient)
          .build();

      expect(repo.baseUrl, 'http://custom:8000');
      expect(repo.apiKey, 'secret');
      expect(repo.maxToolAttempts, 10);
      expect(repo.retryConfig, retryConfig);
      expect(repo.timeoutConfig, timeoutConfig);
    });

    test('builder with partial configuration', () {
      final repo = VLLMChatRepositoryBuilder()
          .baseUrl('http://custom:8000')
          .build();

      expect(repo.baseUrl, 'http://custom:8000');
      expect(repo.maxToolAttempts, 90); // Default
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder with no configuration uses defaults', () {
      final repo = VLLMChatRepositoryBuilder().build();

      expect(repo.baseUrl, 'http://localhost:8000');
      expect(repo.apiKey, isNull);
      expect(repo.maxToolAttempts, 90);
      expect(repo.retryConfig, null);
      expect(repo.timeoutConfig, null);
    });

    test('builder method chaining', () {
      final repo = VLLMChatRepositoryBuilder()
          .baseUrl('http://test:8000')
          .apiKey('key')
          .maxToolAttempts(15)
          .retryConfig(const RetryConfig(maxAttempts: 3))
          .timeoutConfig(const TimeoutConfig(readTimeout: Duration(minutes: 5)))
          .build();

      expect(repo.baseUrl, 'http://test:8000');
      expect(repo.apiKey, 'key');
      expect(repo.maxToolAttempts, 15);
      expect(repo.retryConfig?.maxAttempts, 3);
      expect(repo.timeoutConfig?.readTimeout, const Duration(minutes: 5));
    });

    test('static builder entry point', () {
      final builder = VLLMChatRepository.builder();
      expect(builder, isA<VLLMChatRepositoryBuilder>());
    });

    test('wires capabilities and supportedParams from probes', () {
      // The README workflow probes the server with VLLMRepository and feeds
      // the results back in; both used to be constructor-only.
      const probed = LLMCapabilities(tools: true, embeddings: true);
      final repo = VLLMChatRepositoryBuilder()
          .capabilities(probed)
          .supportedParams({'temperature', 'top_p'})
          .build();

      expect(repo.capabilities, probed);
      expect(repo.capabilitiesForModel('any'), probed);
      expect(repo.supportedParams, {'temperature', 'top_p'});
    });
  });
}
