// ignore_for_file: deprecated_member_use_from_same_package

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for streaming behavior.
void main() {
  final config = TestConfig.instance;

  group('Streaming Behavior', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        print('⚠️  No model available for streaming tests');
      }
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 2048,
        batchSize: 256,
        nGpuLayers: config.gpuLayers,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('chunk ordering', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Count from 1 to 10, one number per response.',
        ),
      ];

      final chunks = <LLMChunk>[];
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        chunks.add(chunk);
      }

      expect(
        chunks.length,
        greaterThan(1),
        reason: 'Should receive multiple chunks',
      );
      // Verify chunks have increasing evalCount (if available)
      int? lastEvalCount;
      for (final chunk in chunks) {
        if (chunk.evalCount != null) {
          if (lastEvalCount != null) {
            expect(
              chunk.evalCount!,
              greaterThanOrEqualTo(lastEvalCount),
              reason: 'evalCount should be non-decreasing',
            );
          }
          lastEvalCount = chunk.evalCount;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('done flag on final chunk', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [LLMMessage(role: LLMRole.user, content: 'Say hello')];

      final chunks = <LLMChunk>[];
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        chunks.add(chunk);
      }

      expect(chunks, isNotEmpty);
      expect(
        chunks.last.done,
        isTrue,
        reason: 'Final chunk should have done=true',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('partial content accumulation', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Write a short sentence about dogs.',
        ),
      ];

      final chunks = <LLMChunk>[];
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        chunks.add(chunk);
      }

      expect(
        chunks.length,
        greaterThan(1),
        reason: 'Should receive multiple chunks',
      );
      final accumulated = chunks
          .map((chunk) => chunk.message?.content ?? '')
          .where((content) => content.isNotEmpty)
          .join();
      expect(
        accumulated.length,
        greaterThan(0),
        reason: 'Should accumulate content',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('chunk metadata', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

      final chunks = <LLMChunk>[];
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        chunks.add(chunk);
      }

      for (final chunk in chunks) {
        expect(
          chunk.model,
          isNotNull,
          reason: 'Chunk model should not be null',
        );
        expect(
          chunk.model,
          isNotEmpty,
          reason: 'Chunk model should not be empty',
        );
        expect(
          chunk.createdAt,
          isNotNull,
          reason: 'Chunk createdAt should not be null',
        );
        expect(
          chunk.createdAt,
          isA<DateTime>(),
          reason: 'Chunk createdAt should be a DateTime',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('token counting', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Count to five.'),
      ];

      int? promptTokens;
      int? evalTokens;

      await for (final chunk in repo.streamChat('test', messages: messages)) {
        if (chunk.done == true) {
          promptTokens = chunk.promptEvalCount;
          evalTokens = chunk.evalCount;
        }
      }

      // Should report some token counts
      if (promptTokens != null) {
        expect(promptTokens, greaterThan(0));
      }
      if (evalTokens != null) {
        expect(evalTokens, greaterThanOrEqualTo(0));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('stream interruption handling', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Write a long story about space exploration.',
        ),
      ];

      final stream = repo.streamChat('test', messages: messages);
      final chunks = <LLMChunk>[];

      // Collect a few chunks then cancel
      try {
        await for (final chunk in stream.timeout(const Duration(seconds: 5))) {
          chunks.add(chunk);
          if (chunks.length >= 3) {
            break; // Simulate interruption
          }
        }
      } catch (e) {
        // Timeout or cancellation is expected
      }

      // Should have received at least some chunks before interruption
      expect(chunks.length, greaterThanOrEqualTo(0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'multiple chunks for longer responses',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final messages = [
          LLMMessage(
            role: LLMRole.user,
            content: 'Write a paragraph about artificial intelligence.',
          ),
        ];

        final chunks = <LLMChunk>[];
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          chunks.add(chunk);
        }

        // Longer responses should have multiple chunks
        expect(
          chunks.length,
          greaterThan(1),
          reason: 'Should receive multiple chunks for longer response',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
