import 'package:llm_vllm/llm_vllm.dart';
import 'package:llm_vllm/src/pool/semaphore.dart';
import 'package:test/test.dart';

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

      await Future<void>.delayed(Duration.zero);
      expect(released, false);
      expect(s.waiting, 1);

      s.release();
      await waiter;
      expect(released, true);
      expect(s.waiting, 0);
    });

    test('acquireWithTimeout throws VLLMQueueTimeoutException', () async {
      final s = Semaphore(1);
      await s.acquire();

      expect(
        () => s.acquireWithTimeout(const Duration(milliseconds: 10)),
        throwsA(isA<VLLMQueueTimeoutException>()),
      );
    });
  });

  group('VLLMModelConfig.matches', () {
    test('exact match', () {
      const c = VLLMModelConfig(pattern: 'Qwen/Qwen3-4B');
      expect(c.matches('Qwen/Qwen3-4B'), true);
      expect(c.matches('Qwen/Qwen3-8B'), false);
    });

    test('wildcard match', () {
      const c = VLLMModelConfig(pattern: 'Qwen/*');
      expect(c.matches('Qwen/Qwen3-4B'), true);
      expect(c.matches('meta-llama/Llama-3.2-3B'), false);
    });
  });

  group('VLLMInstanceConfig', () {
    test('acceptsModel empty exclusiveModels accepts all', () {
      const c = VLLMInstanceConfig(baseUrl: 'http://x');
      expect(c.acceptsModel('anything'), true);
    });

    test('acceptsModel filters exclusive models', () {
      const c = VLLMInstanceConfig(
        baseUrl: 'http://x',
        exclusiveModels: ['large-model'],
      );
      expect(c.acceptsModel('large-model'), true);
      expect(c.acceptsModel('small-model'), false);
    });

    test('prefersModel returns true only for preferredModels', () {
      const c = VLLMInstanceConfig(
        baseUrl: 'http://x',
        preferredModels: ['small-model'],
      );
      expect(c.prefersModel('small-model'), true);
      expect(c.prefersModel('large-model'), false);
    });
  });

  group('VLLMPool construction', () {
    test('creates via constructor', () {
      final pool = VLLMPool(
        instances: [const VLLMInstanceConfig(baseUrl: 'http://localhost')],
      );
      final stats = pool.stats();
      expect(stats.instances.length, 1);
      expect(stats.instances.first.baseUrl, 'http://localhost');
      expect(stats.instances.first.maxConcurrent, 3);
      pool.dispose();
    });

    test('creates via builder', () {
      final pool = VLLMPool.builder()
          .addInstance(
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu1:8000',
              apiKey: 'a',
              maxConcurrent: 4,
            ),
          )
          .addInstance(
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu2:8000',
              maxConcurrent: 1,
            ),
          )
          .addModelConfig(
            const VLLMModelConfig(
              pattern: 'large-model',
              maxConcurrent: 1,
              exclusive: true,
            ),
          )
          .queueTimeout(const Duration(seconds: 10))
          .maxQueueDepth(100)
          .build();

      final stats = pool.stats();
      expect(stats.instances.length, 2);
      expect(stats.healthyInstances, 2);
      expect(pool.queueTimeout, const Duration(seconds: 10));
      expect(pool.maxQueueDepth, 100);
      expect(pool.modelConfigs.length, 1);
      pool.dispose();
    });

    test('instances() replaces previous entries', () {
      final pool = VLLMPoolBuilder()
          .addInstance(const VLLMInstanceConfig(baseUrl: 'http://old'))
          .instances([const VLLMInstanceConfig(baseUrl: 'http://new')])
          .build();

      expect(pool.stats().instances.length, 1);
      expect(pool.stats().instances.first.baseUrl, 'http://new');
      pool.dispose();
    });
  });

  group('VLLMPool routing', () {
    test(
      'throws VLLMNoEligibleInstanceException when no instance accepts model',
      () {
        final pool = VLLMPool(
          instances: [
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu1:8000',
              exclusiveModels: ['large-model'],
            ),
          ],
        );

        expect(
          () => pool
              .streamChat(
                'small-model',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              )
              .toList(),
          throwsA(isA<VLLMNoEligibleInstanceException>()),
        );
        pool.dispose();
      },
    );

    test('throws VLLMQueueFullException when maxQueueDepth reached', () {
      final pool = VLLMPool(
        instances: [
          const VLLMInstanceConfig(
            baseUrl: 'http://gpu1:8000',
            maxConcurrent: 1,
          ),
        ],
        maxQueueDepth: 0,
      );

      expect(
        () => pool
            .streamChat(
              'small-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<VLLMQueueFullException>()),
      );
      pool.dispose();
    });
  });
}
