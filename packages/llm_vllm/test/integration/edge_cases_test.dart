/// Integration tests for Edge Cases
///
/// Part of the comprehensive VLLM integration test suite.
library;

import 'dart:async';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('VLLM Integration Tests - Edge Cases', () {
    late VLLMChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Edge Case Tests', () {
      test(
        'empty message content',
        () async {
          final messages = [LLMMessage(role: LLMRole.user, content: '')];

          try {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
            expect(chunks, isNotEmpty);
          } on LLMApiException catch (error) {
            expect(
              error.statusCode,
              anyOf(equals(400), equals(422)),
              reason: 'Some OpenAI-compatible servers reject empty content.',
            );
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'very long single message',
        () async {
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
    });
  });
}
