/// Integration tests for VLLMPool.
library;

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

final _shortMsg = [LLMMessage(role: LLMRole.user, content: 'Say ok.')];

VLLMInstanceConfig _instance({
  String? url,
  int maxConcurrent = 2,
  List<String> exclusiveModels = const [],
  List<String> preferredModels = const [],
  bool preferEmbedding = false,
}) => VLLMInstanceConfig(
  baseUrl: url ?? baseUrl,
  apiKey: apiKey,
  maxConcurrent: maxConcurrent,
  exclusiveModels: exclusiveModels,
  preferredModels: preferredModels,
  preferEmbedding: preferEmbedding,
  timeoutConfig: const TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 2),
  ),
  retryConfig: const RetryConfig(maxAttempts: 2),
);

void main() {
  group('VLLMPool Integration Tests', () {
    test(
      'streamChat routes through pool',
      () async {
        final pool = VLLMPool(instances: [_instance()]);
        addTearDown(pool.dispose);

        final chunks = await pool
            .streamChat(chatModel, messages: _shortMsg)
            .timeout(const Duration(minutes: 2))
            .toList();

        expect(chunks, isNotEmpty);
        expect(pool.stats().instances.single.baseUrl, baseUrl);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('exclusiveModels rejects ineligible model', () {
      final pool = VLLMPool(
        instances: [
          _instance(exclusiveModels: ['different-model']),
        ],
      );
      addTearDown(pool.dispose);

      expect(
        () => pool.streamChat(chatModel, messages: _shortMsg).toList(),
        throwsA(isA<VLLMNoEligibleInstanceException>()),
      );
    }, tags: ['integration']);

    test(
      'embed routes through embedding-preferred instance',
      () async {
        // vLLM serves one model per process, so the embedding model runs as
        // its own instance. Routing an embed call to the chat instance is a
        // 404 — which is exactly what preferEmbedding exists to prevent.
        final pool = VLLMPool(
          instances: [
            _instance(preferredModels: [chatModel]),
            _instance(url: embeddingBaseUrl, preferEmbedding: true),
          ],
        );
        addTearDown(pool.dispose);

        final embeddings = await pool
            .embed(model: embeddingModel, messages: ['hello'])
            .timeout(const Duration(minutes: 2));

        expect(embeddings, isNotEmpty);
        expect(embeddings.single.embedding, isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 3)),
      skip: embeddingTestsEnabled
          ? false
          : 'Set VLLM_ENABLE_EMBEDDING_TESTS=true',
    );

    test('builder creates pool with queue settings', () {
      final pool = VLLMPool.builder()
          .addInstance(_instance())
          .addModelConfig(VLLMModelConfig(pattern: chatModel, maxConcurrent: 1))
          .queueTimeout(const Duration(seconds: 30))
          .maxQueueDepth(10)
          .build();
      addTearDown(pool.dispose);

      expect(pool.queueTimeout, const Duration(seconds: 30));
      expect(pool.maxQueueDepth, 10);
      expect(pool.modelConfigs.single.matches(chatModel), true);
    }, tags: ['integration']);
  });
}
