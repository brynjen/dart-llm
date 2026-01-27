/// Integration tests for Error Handling
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Error Handling', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Error Handling Tests', () {
      test(
        'invalid model name',
        () async {
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          await expectLater(
            repo.streamChat('non-existent-model-12345', messages: messages),
            emitsError(isA<LLMApiException>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'empty messages array',
        () async {
          await expectLater(
            repo.streamChat(chatModel, messages: []),
            emitsError(isA<LLMApiException>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'invalid base URL',
        () async {
          final badRepo = createRepository(
            customBaseUrl: 'http://invalid-host-12345:11434',
          );
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          await expectLater(
            badRepo.streamChat(chatModel, messages: messages),
            emitsError(anything),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'timeout configuration',
        () async {
          final timeoutRepo = createRepository(
            timeoutConfig: const TimeoutConfig(
              connectionTimeout: Duration(seconds: 1),
              readTimeout: Duration(milliseconds: 1),
            ),
          );

          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          // Should timeout due to very short read timeout
          await expectLater(
            timeoutRepo.streamChat(chatModel, messages: messages),
            emitsError(anything),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'rate limiting handling',
        () async {
          // Make rapid requests to potentially trigger rate limiting
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          // Make multiple rapid requests
          final futures = List.generate(10, (_) {
            return collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
          });

          // At least some should succeed, but rate limiting might occur
          final results = await Future.wait(futures, eagerError: false);
          expect(results.length, equals(10));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'malformed responses handling',
        () async {
          // Test with a request that might cause issues
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Generate a response with special characters: ${String.fromCharCodes(List.generate(1000, (i) => i % 256))}',
            ),
          ];

          // Should either complete or fail gracefully
          try {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
            expect(chunks, isA<List<LLMChunk>>());
          } catch (e) {
            // Should fail gracefully with a proper exception
            expect(e, isA<Exception>());
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
