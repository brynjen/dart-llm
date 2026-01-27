/// Integration tests for Edge Cases
///
/// Part of the comprehensive ChatGPT integration test suite.
///
/// Requires API key to be set via OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN environment variable.
library;

import 'dart:async';

import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('ChatGPT Integration Tests - Edge Cases', () {
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

    group('Edge Case Tests', () {
      test(
        'empty message content',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [LLMMessage(role: LLMRole.user, content: '')];

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
        'very long single message',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final longMessage = 'This is a test. ' * 500; // ~7500 characters
          final messages = [
            LLMMessage(role: LLMRole.user, content: longMessage),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(minutes: 3),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'unicode edge cases',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          const unicodeText = 'Hello 🌍 你好 مرحبا 🚀';
          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Echo: $unicodeText'),
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
        'JSON-like content',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          const jsonLikeContent =
              'Here is some JSON: {"key": "value", "number": 42}';
          final messages = [
            LLMMessage(role: LLMRole.user, content: jsonLikeContent),
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
        'code-like content',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          const codeContent =
              'Here is code: ```dart\nvoid main() {\n  print("test");\n}\n```';
          final messages = [
            LLMMessage(role: LLMRole.user, content: codeContent),
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
        'concurrent requests',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say hello'),
          ];

          final futures = List.generate(5, (_) {
            return collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
          });

          final results = await Future.wait(futures);
          for (final chunks in results) {
            expect(chunks, isNotEmpty);
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'extremely long conversation',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = <LLMMessage>[];
          for (int i = 1; i <= 10; i++) {
            messages.add(
              LLMMessage(
                role: LLMRole.user,
                content: 'Turn $i: What is $i + $i?',
              ),
            );
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
            messages.add(
              LLMMessage(
                role: LLMRole.assistant,
                content: extractContent(chunks),
              ),
            );
          }

          expect(messages.length, equals(20));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 15)),
      );

      test(
        'rapid successive requests',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Say "test"'),
          ];

          // Make rapid successive requests
          for (int i = 0; i < 3; i++) {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
            expect(chunks, isNotEmpty);
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  });
}
