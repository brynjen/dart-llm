import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('LLMRepositoryFeatures', () {
    test('caches chatResponse when useCache is enabled', () async {
      final cache = MemoryResponseCache();
      final repo = _FeaturedMockRepository(responseCache: cache);
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

      repo.setResponse('first');
      final first = await repo.chatResponse(
        'test-model',
        messages: messages,
        options: const LLMChatOptions(useCache: true),
      );

      repo.setResponse('second');
      final second = await repo.chatResponse(
        'test-model',
        messages: messages,
        options: const LLMChatOptions(useCache: true),
      );

      expect(first.content, 'first');
      expect(second.content, 'first');
      expect(cache.stats.hits, 1);
    });

    test('records metrics around chatResponse', () async {
      final metrics = DefaultLLMMetrics();
      final repo = _FeaturedMockRepository(metrics: metrics);
      repo.setResponse('ok');

      await repo.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
      );

      final snapshot = metrics.getMetrics();
      expect(snapshot['test-model.total_requests'], 1);
      expect(snapshot['test-model.successful_requests'], 1);
      expect(snapshot['test-model.total_generated_tokens'], 5);
    });

    test('can disable metrics per request', () async {
      final metrics = DefaultLLMMetrics();
      final repo = _FeaturedMockRepository(metrics: metrics);
      repo.setResponse('ok');

      await repo.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        options: const LLMChatOptions(recordMetrics: false),
      );

      expect(metrics.getMetrics(), isEmpty);
    });
  });
}

class _FeaturedMockRepository extends MockLLMChatRepository
    with LLMRepositoryFeatures {
  _FeaturedMockRepository({this.responseCache, this.metrics});

  @override
  final ResponseCache? responseCache;

  @override
  final LLMMetrics? metrics;
}
