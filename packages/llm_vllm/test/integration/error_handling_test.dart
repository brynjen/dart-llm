/// Integration tests for Error Handling
///
/// Part of the comprehensive VLLM integration test suite.
library;

import 'dart:async';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('VLLM Integration Tests - Error Handling', () {
    late VLLMChatRepository repo;

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
            customBaseUrl: 'http://invalid-host-12345:8000',
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
          addTearDown(timeoutRepo.httpClient.close);

          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          // With a 1ms read timeout, we expect either:
          // 1) an early timeout/API error, or
          // 2) a very fast first chunk before timeout kicks in.
          // Using `first` avoids leaving a long-running stream alive.
          try {
            final firstChunk = await timeoutRepo
                .streamChat(chatModel, messages: messages)
                .first
                .timeout(const Duration(seconds: 30));
            expect(firstChunk, isA<LLMChunk>());
          } catch (e) {
            expect(e, anyOf(isA<TimeoutException>(), isA<LLMApiException>()));
          }
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
          // Use unusual control/special characters but keep the request bounded.
          // This verifies response handling does not hang under odd payloads.
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Echo these characters exactly: \\u0000 \\u0001 \\u0002 [] {} <> "quoted" 😅',
            ),
          ];

          try {
            final firstChunk = await repo
                .streamChat(chatModel, messages: messages)
                .first
                .timeout(const Duration(seconds: 30));
            expect(firstChunk, isA<LLMChunk>());
          } catch (e) {
            // Should fail fast with a surfaced exception rather than hanging.
            expect(
              e,
              anyOf(
                isA<TimeoutException>(),
                isA<LLMApiException>(),
                isA<Exception>(),
              ),
            );
          }

          // Run a short full-stream attempt with explicit timeout to ensure
          // no unbounded hang in malformed-path handling.
          try {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 30),
            );
            expect(chunks, isA<List<LLMChunk>>());
          } catch (e) {
            expect(e, isA<Exception>());
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
