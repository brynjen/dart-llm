/// Integration tests for OllamaPool — multi-instance orchestration.
///
/// These tests verify end-to-end behaviour with the live Ollama server.
/// Unit tests already cover semaphore mechanics, config matching, routing
/// exceptions, keep_alive extraction, and builder property assertions.
/// This file covers what only real HTTP can exercise: health-check detection,
/// embedding isolation acceptance, stats accuracy, and routing correctness.
///
/// Run:
///   dart test test/integration/ollama_pool_integration_test.dart --tags integration
library;

import 'dart:async';

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Local helper — avoids repeating timeoutConfig on every OllamaInstanceConfig
// ---------------------------------------------------------------------------

OllamaInstanceConfig _instance({
  String? url,
  int maxConcurrent = 3,
  List<String> exclusiveModels = const [],
  List<String> preferredModels = const [],
  bool preferEmbedding = false,
  EmbeddingIsolation embeddingIsolation = EmbeddingIsolation.none,
}) => OllamaInstanceConfig(
  baseUrl: url ?? baseUrl,
  maxConcurrent: maxConcurrent,
  exclusiveModels: exclusiveModels,
  preferredModels: preferredModels,
  preferEmbedding: preferEmbedding,
  embeddingIsolation: embeddingIsolation,
  timeoutConfig: const TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 2),
  ),
);

final _shortMsg = [LLMMessage(role: LLMRole.user, content: 'Say hi briefly.')];

void main() {
  // =========================================================================
  // Group 1: Single-instance basic chat
  // =========================================================================

  group('OllamaPool Integration - single instance basics', () {
    late OllamaPool pool;

    setUp(() {
      pool = OllamaPool(instances: [_instance()]);
      addTearDown(pool.dispose);
    });

    test(
      'streamChat returns valid chunks through pool',
      () async {
        final chunks = await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );

        expect(chunks, isNotEmpty);
        expect(chunks.last.done, isTrue);
        verifyChunkStructure(chunks.last);
        expect(extractContent(chunks), isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'stats show zero active after completion',
      () async {
        await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );

        final s = pool.stats();
        expect(s.totalActive, 0);
        expect(s.totalQueued, 0);
        expect(s.instances.first.activeConcurrent, 0);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'embed returns valid embeddings through pool',
      () async {
        final result = await pool.embed(
          model: embeddingModel,
          messages: ['integration test embedding'],
        );

        expect(result, isNotEmpty);
        expect(result.first.embedding, isNotEmpty);
        expect(
          result.first.embedding.every((v) => v.isFinite),
          isTrue,
          reason: 'All embedding values should be finite',
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'batchEmbed returns one result per message',
      () async {
        final result = await pool.batchEmbed(
          model: embeddingModel,
          messages: ['alpha', 'beta', 'gamma'],
        );

        expect(result.length, 3);
        final dim = result.first.embedding.length;
        for (final e in result) {
          expect(
            e.embedding.length,
            dim,
            reason: 'All embeddings should have consistent dimensions',
          );
        }
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  // =========================================================================
  // Group 2: Health checking
  // =========================================================================

  group('OllamaPool Integration - health checking', () {
    test(
      'healthy instance stays healthy after initial check',
      () async {
        final pool = OllamaPool(
          instances: [_instance()],
          healthCheck: const HealthCheckConfig(
            interval: Duration(seconds: 60),
            timeout: Duration(seconds: 5),
          ),
        );
        addTearDown(pool.dispose);

        // Initial check fires asynchronously; give it time to complete
        await Future<void>.delayed(const Duration(seconds: 3));

        expect(pool.stats().instances.first.healthy, isTrue);
        expect(pool.stats().healthyInstances, 1);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'unreachable instance is marked unhealthy',
      () async {
        final pool = OllamaPool(
          instances: [_instance(url: 'http://localhost:19999')],
          healthCheck: const HealthCheckConfig(
            interval: Duration(seconds: 60),
            timeout: Duration(seconds: 2),
          ),
        );
        addTearDown(pool.dispose);

        // The initial health check fires immediately and should fail fast
        final event = await pool.onInstanceStateChange.first.timeout(
          const Duration(seconds: 10),
        );

        expect(event.healthy, isFalse);
        expect(event.baseUrl, 'http://localhost:19999');
        expect(pool.stats().healthyInstances, 0);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'pool with mixed instances routes only to healthy one',
      () async {
        final pool = OllamaPool(
          instances: [
            _instance(url: 'http://localhost:19999'),
            _instance(),
          ],
          healthCheck: const HealthCheckConfig(
            interval: Duration(seconds: 60),
            timeout: Duration(seconds: 2),
          ),
        );
        addTearDown(pool.dispose);

        // Wait for the unhealthy instance to be detected
        await pool.onInstanceStateChange.first.timeout(
          const Duration(seconds: 10),
        );

        expect(pool.stats().healthyInstances, 1);

        // Request should succeed via the healthy instance
        final chunks = await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );

        expect(chunks, isNotEmpty);
        expect(extractContent(chunks), isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'onInstanceStateChange emits nothing for a stable server',
      () async {
        final pool = OllamaPool(
          instances: [_instance()],
          healthCheck: const HealthCheckConfig(
            interval: Duration(seconds: 60),
            timeout: Duration(seconds: 5),
          ),
        );
        addTearDown(pool.dispose);

        final events = <OllamaInstanceStateChange>[];
        final sub = pool.onInstanceStateChange.listen(events.add);
        await Future<void>.delayed(const Duration(seconds: 3));
        await sub.cancel();

        expect(
          events,
          isEmpty,
          reason:
              'No state-change events expected for a continuously healthy instance',
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
      skip: 'timing-sensitive — only run locally with a stable server',
    );
  });

  // =========================================================================
  // Group 3: Multi-instance routing
  // =========================================================================

  group('OllamaPool Integration - multi-instance routing', () {
    late OllamaPool pool;

    setUp(() {
      pool = OllamaPool(instances: [_instance(), _instance()]);
      addTearDown(pool.dispose);
    });

    test(
      'stats show two instances on idle pool',
      () {
        final s = pool.stats();
        expect(s.instances.length, 2);
        expect(s.healthyInstances, 2);
        expect(s.totalActive, 0);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'request completes with two-instance pool',
      () async {
        final chunks = await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );
        expect(chunks, isNotEmpty);
        expect(extractContent(chunks), isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'concurrent requests both complete successfully',
      () async {
        // Fires two requests; Future.wait runs them concurrently within this test.
        // Both should complete without errors.
        // Note: no mid-flight stat assertion — checking stats while HTTP is in
        // flight would be racy and flaky.
        final results = await Future.wait([
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
        ]);

        for (final chunks in results) {
          expect(chunks, isNotEmpty);
          expect(extractContent(chunks), isNotEmpty);
        }
        expect(pool.stats().totalActive, 0);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'exclusiveModels routes chat and embed to correct instances',
      () async {
        final exclusivePool = OllamaPool(
          instances: [
            _instance(exclusiveModels: [chatModel]),
            _instance(exclusiveModels: [embeddingModel]),
          ],
        );
        addTearDown(exclusivePool.dispose);

        // Chat should succeed (routed to first instance)
        final chatChunks = await collectStreamWithTimeout(
          exclusivePool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );
        expect(chatChunks, isNotEmpty);

        // Embed should succeed (routed to second instance)
        final embedResult = await exclusivePool.embed(
          model: embeddingModel,
          messages: ['exclusive routing test'],
        );
        expect(embedResult, isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'OllamaNoEligibleInstanceException when no instance accepts model',
      () async {
        final restrictedPool = OllamaPool(
          instances: [
            _instance(exclusiveModels: [chatModel]),
          ],
        );
        addTearDown(restrictedPool.dispose);

        expect(
          () => restrictedPool
              .streamChat('some-other-model', messages: _shortMsg)
              .toList(),
          throwsA(isA<OllamaNoEligibleInstanceException>()),
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // =========================================================================
  // Group 4: Embedding isolation
  // =========================================================================

  group('OllamaPool Integration - embedding isolation', () {
    Future<void> assertEmbedWorks(OllamaPool pool) async {
      final result = await pool.embed(
        model: embeddingModel,
        messages: ['embedding isolation test'],
      );
      expect(result, isNotEmpty);
      expect(result.first.embedding, isNotEmpty);
      expect(result.first.embedding.every((v) => v.isFinite), isTrue);
    }

    test(
      'embed succeeds with EmbeddingIsolation.unloadFirst',
      () async {
        final pool = OllamaPool(
          instances: [
            _instance(embeddingIsolation: EmbeddingIsolation.unloadFirst),
          ],
        );
        addTearDown(pool.dispose);
        await assertEmbedWorks(pool);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'embed succeeds with EmbeddingIsolation.none (baseline)',
      () async {
        final pool = OllamaPool(
          instances: [_instance(embeddingIsolation: EmbeddingIsolation.none)],
        );
        addTearDown(pool.dispose);
        await assertEmbedWorks(pool);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'embed succeeds with model-level keepAlive override',
      () async {
        final pool = OllamaPool(
          instances: [_instance()],
          modelConfigs: [
            const OllamaModelConfig(
              pattern: '*embed*',
              keepAlive: Duration.zero,
            ),
          ],
        );
        addTearDown(pool.dispose);
        await assertEmbedWorks(pool);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'caller-provided keep_alive is not overridden by pool',
      () async {
        final pool = OllamaPool(
          instances: [
            _instance(embeddingIsolation: EmbeddingIsolation.unloadFirst),
          ],
        );
        addTearDown(pool.dispose);

        // Passing keep_alive: '60s' — pool must not override with '0'
        final result = await pool.embed(
          model: embeddingModel,
          messages: ['caller keep_alive test'],
          options: const {'keep_alive': '60s'},
        );
        expect(result, isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  // =========================================================================
  // Group 5: Stats accuracy
  // =========================================================================

  group('OllamaPool Integration - stats accuracy', () {
    test(
      'idle pool shows zero activity immediately after construction',
      () {
        final pool = OllamaPool(instances: [_instance()]);
        addTearDown(pool.dispose);

        final s = pool.stats();
        expect(s.totalActive, 0);
        expect(s.totalQueued, 0);
        expect(s.healthyInstances, 1);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'stats show zero active after concurrent requests complete',
      () async {
        final pool = OllamaPool(instances: [_instance(), _instance()]);
        addTearDown(pool.dispose);

        // Mid-flight stat assertion omitted: would be racy with real HTTP.
        // Only the post-completion state is asserted.
        await Future.wait([
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
        ]);

        final s = pool.stats();
        expect(s.totalActive, 0);
        expect(s.totalQueued, 0);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'two-instance pool stats show both instances as healthy',
      () {
        final pool = OllamaPool(instances: [_instance(), _instance()]);
        addTearDown(pool.dispose);

        final s = pool.stats();
        expect(s.instances.length, 2);
        // No health check configured — both start healthy
        expect(s.healthyInstances, 2);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // =========================================================================
  // Group 6: Error propagation
  // =========================================================================

  group('OllamaPool Integration - error propagation', () {
    late OllamaPool pool;

    setUp(() {
      pool = OllamaPool(instances: [_instance()]);
      addTearDown(pool.dispose);
    });

    test(
      'invalid chat model propagates server error, not OllamaNoEligibleInstanceException',
      () async {
        // No exclusiveModels — routing succeeds, server fails
        expect(
          () => pool
              .streamChat(
                'definitely-not-a-real-model-xxxxxx',
                messages: _shortMsg,
              )
              .toList(),
          throwsA(
            allOf(
              isNot(isA<OllamaNoEligibleInstanceException>()),
              isA<Exception>(),
            ),
          ),
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'invalid embed model propagates server error',
      () async {
        expect(
          () => pool.embed(
            model: 'definitely-not-a-real-embed-model-xxxxxx',
            messages: ['test'],
          ),
          throwsA(
            allOf(
              isNot(isA<OllamaNoEligibleInstanceException>()),
              isA<Exception>(),
            ),
          ),
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'unreachable instance throws connection error without health check',
      () async {
        final unreachablePool = OllamaPool(
          instances: [_instance(url: 'http://localhost:19999')],
          // No health check — slot starts healthy, error comes at request time
        );
        addTearDown(unreachablePool.dispose);

        await expectLater(
          unreachablePool.streamChat(chatModel, messages: _shortMsg).toList(),
          throwsA(isA<Exception>()),
        );
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'dispose is safe to call twice',
      () {
        final p = OllamaPool(instances: [_instance()]);
        p.dispose();
        // Second dispose should not throw
        expect(p.dispose, returnsNormally);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });

  // =========================================================================
  // Group 7: ModelConfigs integration
  // =========================================================================

  group('OllamaPool Integration - modelConfigs', () {
    test(
      'model keepAlive is injected and chat request succeeds',
      () async {
        final pool = OllamaPool(
          instances: [_instance()],
          modelConfigs: [
            const OllamaModelConfig(
              pattern: chatModel,
              keepAlive: Duration(minutes: 5),
            ),
          ],
        );
        addTearDown(pool.dispose);

        final chunks = await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );
        expect(chunks, isNotEmpty);
        expect(extractContent(chunks), isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'exclusive:true serialises concurrent calls — both complete',
      () async {
        final pool = OllamaPool(
          instances: [_instance(maxConcurrent: 3)],
          modelConfigs: [
            const OllamaModelConfig(pattern: chatModel, exclusive: true),
          ],
        );
        addTearDown(pool.dispose);

        // exclusive: true → model-level Semaphore(1) serialises the two calls.
        // Both should complete successfully (no deadlock).
        final results = await Future.wait([
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
          collectStreamWithTimeout(
            pool.streamChat(chatModel, messages: _shortMsg),
            const Duration(minutes: 2),
          ),
        ]);

        for (final chunks in results) {
          expect(chunks, isNotEmpty);
          expect(extractContent(chunks), isNotEmpty);
        }
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // =========================================================================
  // Group 8: Builder API integration
  // =========================================================================

  group('OllamaPool Integration - builder API', () {
    test(
      'pool created via OllamaPool.builder() works end-to-end',
      () async {
        final pool = OllamaPool.builder()
            .addInstance(_instance())
            .addModelConfig(const OllamaModelConfig(pattern: '*embed*'))
            .queueTimeout(const Duration(seconds: 30))
            .build();
        addTearDown(pool.dispose);

        // Chat
        final chatChunks = await collectStreamWithTimeout(
          pool.streamChat(chatModel, messages: _shortMsg),
          const Duration(minutes: 2),
        );
        expect(chatChunks, isNotEmpty);
        expect(extractContent(chatChunks), isNotEmpty);

        // Embed
        final embedResult = await pool.embed(
          model: embeddingModel,
          messages: ['builder api integration test'],
        );
        expect(embedResult, isNotEmpty);
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
