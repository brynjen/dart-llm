/// Integration tests for Basic Chat
///
/// Part of the comprehensive ChatGPT integration test suite.
///
/// Requires API key to be set via OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN environment variable.
library;

import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('ChatGPT Integration Tests - Basic Chat', () {
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

    group('Basic Chat Tests', () {
      test(
        'streamChat receives streaming response',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Hello, please respond with a brief greeting.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(
            chunks,
            isNotEmpty,
            reason: 'Should receive at least one chunk',
          );
          final finalChunk = chunks.last;
          expect(finalChunk.done, isTrue, reason: 'Final chunk should be done');
          verifyChunkStructure(finalChunk);

          final content = extractContent(chunks);
          expect(content.isNotEmpty, isTrue, reason: 'Should receive content');
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'chatResponse receives complete non-streaming response',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say "test" in one word.'),
          ];

          final response = await repo
              .chatResponse(chatModel, messages: messages)
              .timeout(const Duration(seconds: 90));

          verifyResponseStructure(response);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'handles empty content response',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Respond with just a period.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          expect(chunks.last.done, isTrue);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'handles very long responses',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Write a very long story about a robot learning to paint. Make it at least 500 words.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(minutes: 3),
          );

          expect(chunks, isNotEmpty);
          final content = extractContent(chunks);
          expect(
            content.length,
            greaterThan(100),
            reason: 'Should receive substantial content',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'handles special characters in content',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          const specialText =
              'Hello! 🌍 你好 مرحبا\n\tJSON: {"key": "value"}\nCode: `print("test")`';
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Echo back exactly: $specialText',
            ),
          ];

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

      test(
        'handles system messages',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.system,
              content:
                  'You are a helpful assistant that always responds in uppercase.',
            ),
            LLMMessage(role: LLMRole.user, content: 'Say hello'),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'handles multiple system messages',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.system,
              content: 'You are a helpful assistant.',
            ),
            LLMMessage(role: LLMRole.system, content: 'Always be concise.'),
            LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'handles very short responses',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say only "yes".'),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          final content = extractContent(chunks);
          expect(
            content.length,
            lessThan(20),
            reason: 'Should be a very short response',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'handles response with only whitespace',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Respond with only a space character.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          expect(chunks.last.done, isTrue);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
