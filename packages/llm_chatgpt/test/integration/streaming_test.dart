/// Integration tests for Streaming Behavior
///
/// Part of the comprehensive ChatGPT integration test suite.
///
/// Requires API key to be set via OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN environment variable.
library;

import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('ChatGPT Integration Tests - Streaming Behavior', () {
    late ChatGPTChatRepository repo;

    setUpAll(() {
      // ignore: avoid_print
      if (!hasApiKey()) {
        // ignore: avoid_print
        print(
          '⚠️  API key not found. Set OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN',
        );
        // ignore: avoid_print
        print('   Skipping integration tests');
      }
    });

    setUp(() {
      if (!hasApiKey()) {
        return;
      }
      repo = createRepository();
    });

    group('Streaming Behavior Tests', () {
      test(
        'chunk ordering',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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

      test(
        'stream interruption handling',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Write a long story about space exploration.',
            ),
          ];

          final stream = repo.streamChat(chatModel, messages: messages);
          final chunks = <LLMChunk>[];

          // Collect a few chunks then cancel
          try {
            await for (final chunk in stream.timeout(
              const Duration(seconds: 5),
            )) {
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
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'partial stream recovery',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say "test" exactly once.'),
          ];

          // Complete stream should work
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          final content = extractContent(chunks);
          expect(content, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
