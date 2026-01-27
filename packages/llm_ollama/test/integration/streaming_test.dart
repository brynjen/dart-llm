/// Integration tests for Streaming Behavior
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Streaming Behavior', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Streaming Behavior Tests', () {
      test(
        'chunk ordering',
        () async {
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Count from 1 to 10, one number per response.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

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
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'done flag on final chunk',
        () async {
          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say hello'),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          expect(
            chunks.last.done,
            isTrue,
            reason: 'Final chunk should have done=true',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'partial content accumulation',
        () async {
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Write a short sentence about dogs.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(
            chunks.length,
            greaterThan(1),
            reason: 'Should receive multiple chunks',
          );
          final accumulated = extractContent(chunks);
          expect(
            accumulated.length,
            greaterThan(0),
            reason: 'Should accumulate content',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'chunk metadata',
        () async {
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          for (final chunk in chunks) {
            verifyChunkStructure(chunk);
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
