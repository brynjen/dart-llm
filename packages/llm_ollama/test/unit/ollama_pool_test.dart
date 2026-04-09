import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_ollama/llm_ollama.dart';
import 'package:llm_ollama/src/pool/semaphore.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Embedding response JSON.
const _embedResponse =
    '{"model":"nomic-embed-text","embeddings":[[0.1,0.2]],'
    '"prompt_eval_count":5,"total_duration":1000000,"load_duration":500000}';

// ---------------------------------------------------------------------------
// Semaphore tests
// ---------------------------------------------------------------------------

void main() {
  group('Semaphore', () {
    test('immediately grants permits up to maxCount', () async {
      final s = Semaphore(3);
      expect(s.available, 3);
      await s.acquire();
      expect(s.available, 2);
      await s.acquire();
      expect(s.available, 1);
      await s.acquire();
      expect(s.available, 0);
    });

    test('blocks when at capacity and releases on release()', () async {
      final s = Semaphore(1);
      await s.acquire();
      expect(s.available, 0);

      var released = false;
      final waiter = s.acquire().then((_) => released = true);

      // Still waiting
      await Future<void>.delayed(Duration.zero);
      expect(released, false);
      expect(s.waiting, 1);

      s.release();
      await waiter;
      expect(released, true);
      expect(s.waiting, 0);
    });

    test('preserves FIFO order for waiters', () async {
      final s = Semaphore(1);
      await s.acquire();

      final order = <int>[];
      Future<void> add(int n) => s.acquire().then((_) => order.add(n));

      // Queue 3 waiters
      final f1 = add(1);
      final f2 = add(2);
      final f3 = add(3);
      await Future<void>.delayed(Duration.zero); // Let them queue

      s.release(); // Release for waiter 1
      await f1;
      s.release(); // Release for waiter 2
      await f2;
      s.release(); // Release for waiter 3
      await f3;

      expect(order, [1, 2, 3]);
    });

    test(
      'acquireWithTimeout throws OllamaQueueTimeoutException on timeout',
      () async {
        final s = Semaphore(1);
        await s.acquire(); // fill it

        expect(
          () => s.acquireWithTimeout(const Duration(milliseconds: 10)),
          throwsA(isA<OllamaQueueTimeoutException>()),
        );
      },
    );

    test('acquireWithTimeout removes waiter on timeout', () async {
      final s = Semaphore(1);
      await s.acquire();
      expect(s.waiting, 0);

      // Try to acquire with short timeout — will fail
      await expectLater(
        s.acquireWithTimeout(const Duration(milliseconds: 10)),
        throwsA(isA<OllamaQueueTimeoutException>()),
      );

      // Waiter was cleaned up
      expect(s.waiting, 0);

      // Releasing should restore the available count
      s.release();
      expect(s.available, 1);
    });

    test('available count returns to 0 after all acquired', () async {
      final s = Semaphore(2);
      await s.acquire();
      await s.acquire();
      s.release();
      s.release();
      expect(s.available, 2);
    });
  });

  // -------------------------------------------------------------------------
  // OllamaModelConfig tests
  // -------------------------------------------------------------------------

  group('OllamaModelConfig.matches', () {
    test('exact match', () {
      const c = OllamaModelConfig(pattern: 'llama3.3:70b');
      expect(c.matches('llama3.3:70b'), true);
      expect(c.matches('llama3.3:8b'), false);
    });

    test('wildcard prefix', () {
      const c = OllamaModelConfig(pattern: 'qwen*');
      expect(c.matches('qwen3:4b'), true);
      expect(c.matches('qwen2.5:7b'), true);
      expect(c.matches('llama3.2:3b'), false);
    });

    test('wildcard suffix — tag glob', () {
      const c = OllamaModelConfig(pattern: '*:4b');
      expect(c.matches('qwen3:4b'), true);
      expect(c.matches('llama3.2:4b'), true);
      expect(c.matches('llama3.2:8b'), false);
    });

    test('wildcard infix — embed glob', () {
      const c = OllamaModelConfig(pattern: '*embed*');
      expect(c.matches('nomic-embed-text'), true);
      expect(c.matches('mxbai-embed-large'), true);
      expect(c.matches('llama3.2:3b'), false);
    });

    test('dot in pattern is escaped (not a regex wildcard)', () {
      const c = OllamaModelConfig(pattern: 'llama3.3:70b');
      // '.' should not match arbitrary characters
      expect(c.matches('llama3X3:70b'), false);
    });

    test('keepAliveParam returns correct strings', () {
      expect(
        const OllamaModelConfig(
          pattern: 'x',
          keepAlive: Duration.zero,
        ).keepAliveParam,
        '0',
      );
      expect(
        const OllamaModelConfig(
          pattern: 'x',
          keepAlive: Duration(minutes: 5),
        ).keepAliveParam,
        '300s',
      );
      expect(const OllamaModelConfig(pattern: 'x').keepAliveParam, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // OllamaInstanceConfig tests
  // -------------------------------------------------------------------------

  group('OllamaInstanceConfig', () {
    test('acceptsModel — empty exclusiveModels accepts all', () {
      const c = OllamaInstanceConfig(baseUrl: 'http://x');
      expect(c.acceptsModel('anything'), true);
    });

    test('acceptsModel — with exclusiveModels filters correctly', () {
      const c = OllamaInstanceConfig(
        baseUrl: 'http://x',
        exclusiveModels: ['llama3.3:70b'],
      );
      expect(c.acceptsModel('llama3.3:70b'), true);
      expect(c.acceptsModel('qwen3:4b'), false);
    });

    test('prefersModel returns true only for preferredModels', () {
      const c = OllamaInstanceConfig(
        baseUrl: 'http://x',
        preferredModels: ['qwen3:4b'],
      );
      expect(c.prefersModel('qwen3:4b'), true);
      expect(c.prefersModel('llama3.2:3b'), false);
    });
  });

  // -------------------------------------------------------------------------
  // OllamaPool construction tests
  // -------------------------------------------------------------------------

  group('OllamaPool construction', () {
    test('creates via constructor', () {
      final pool = OllamaPool(
        instances: [const OllamaInstanceConfig(baseUrl: 'http://localhost')],
      );
      final s = pool.stats();
      expect(s.instances.length, 1);
      expect(s.instances.first.baseUrl, 'http://localhost');
      expect(s.instances.first.maxConcurrent, 3);
      pool.dispose();
    });

    test('creates via builder', () {
      final pool = OllamaPool.builder()
          .addInstance(
            const OllamaInstanceConfig(
              baseUrl: 'http://gpu1:11434',
              maxConcurrent: 4,
            ),
          )
          .addInstance(
            const OllamaInstanceConfig(
              baseUrl: 'http://gpu2:11434',
              maxConcurrent: 1,
            ),
          )
          .build();

      final s = pool.stats();
      expect(s.instances.length, 2);
      expect(s.healthyInstances, 2);
      pool.dispose();
    });

    test('stats reports zero active on idle pool', () {
      final pool = OllamaPool(
        instances: [
          const OllamaInstanceConfig(baseUrl: 'http://a'),
          const OllamaInstanceConfig(baseUrl: 'http://b'),
        ],
      );
      final s = pool.stats();
      expect(s.totalActive, 0);
      expect(s.totalQueued, 0);
      pool.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // OllamaPool routing tests (via mock HTTP)
  // -------------------------------------------------------------------------

  group('OllamaPool routing', () {
    test(
      'throws OllamaNoEligibleInstanceException when no instance accepts model',
      () async {
        final pool = OllamaPool(
          instances: [
            const OllamaInstanceConfig(
              baseUrl: 'http://gpu1:11434',
              exclusiveModels: ['llama3.3:70b'],
            ),
          ],
        );

        expect(
          () => pool
              .streamChat(
                'qwen3:4b',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              )
              .toList(),
          throwsA(isA<OllamaNoEligibleInstanceException>()),
        );
        pool.dispose();
      },
    );

    test(
      'throws OllamaQueueFullException when maxQueueDepth reached',
      () async {
        // Create a pool with zero queue depth tolerance
        final pool = OllamaPool(
          instances: [
            const OllamaInstanceConfig(
              baseUrl: 'http://gpu1:11434',
              maxConcurrent: 1,
            ),
          ],
          maxQueueDepth: 0,
        );
        // The guard fires before acquiring the semaphore — even an idle pool
        // with maxQueueDepth: 0 should reject when queue has ≥ 0 entries.
        // (Queue is empty so 0 >= 0 is true — instant reject.)
        expect(
          () => pool
              .streamChat(
                'qwen3:4b',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              )
              .toList(),
          throwsA(isA<OllamaQueueFullException>()),
        );
        pool.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Embed keep_alive injection (via modified OllamaChatRepository)
  // -------------------------------------------------------------------------

  group('OllamaChatRepository embed keep_alive extraction', () {
    test('injects keep_alive as top-level body field', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _embedResponse,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = OllamaChatRepository(httpClient: client);
      await repo.embed(
        model: 'nomic-embed-text',
        messages: ['hello'],
        options: {'keep_alive': '0', 'num_ctx': 512},
      );

      expect(capturedBody['keep_alive'], '0');
      // keep_alive should NOT appear inside options
      final bodyOptions =
          capturedBody['options'] as Map<String, dynamic>? ?? {};
      expect(bodyOptions.containsKey('keep_alive'), false);
      expect(bodyOptions['num_ctx'], 512);
    });

    test('keepAlive alias also works', () async {
      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = json.decode(request.body) as Map<String, dynamic>;
        return http.Response(
          _embedResponse,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = OllamaChatRepository(httpClient: client);
      await repo.embed(
        model: 'nomic-embed-text',
        messages: ['hello'],
        options: {'keepAlive': '300s'},
      );

      expect(capturedBody['keep_alive'], '300s');
    });

    test(
      'omits options field when options is empty after extraction',
      () async {
        late Map<String, dynamic> capturedBody;
        final client = MockClient((request) async {
          capturedBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            _embedResponse,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final repo = OllamaChatRepository(httpClient: client);
        await repo.embed(
          model: 'nomic-embed-text',
          messages: ['hello'],
          options: {'keep_alive': '0'},
        );

        expect(capturedBody['keep_alive'], '0');
        expect(capturedBody.containsKey('options'), false);
      },
    );
  });

  // -------------------------------------------------------------------------
  // OllamaPoolBuilder tests
  // -------------------------------------------------------------------------

  group('OllamaPoolBuilder', () {
    test('fluent API builds pool correctly', () {
      final pool = OllamaPoolBuilder()
          .addInstance(
            const OllamaInstanceConfig(
              baseUrl: 'http://gpu1',
              maxConcurrent: 4,
              preferEmbedding: true,
            ),
          )
          .addModelConfig(
            const OllamaModelConfig(
              pattern: '*embed*',
              keepAlive: Duration(minutes: 30),
            ),
          )
          .queueTimeout(const Duration(seconds: 10))
          .maxQueueDepth(100)
          .build();

      expect(pool.queueTimeout, const Duration(seconds: 10));
      expect(pool.maxQueueDepth, 100);
      expect(pool.modelConfigs.length, 1);
      final s = pool.stats();
      expect(s.instances.first.baseUrl, 'http://gpu1');
      pool.dispose();
    });

    test('instances() replaces previous entries', () {
      final pool = OllamaPoolBuilder()
          .addInstance(const OllamaInstanceConfig(baseUrl: 'http://old'))
          .instances([const OllamaInstanceConfig(baseUrl: 'http://new')])
          .build();

      expect(pool.stats().instances.length, 1);
      expect(pool.stats().instances.first.baseUrl, 'http://new');
      pool.dispose();
    });
  });
}
