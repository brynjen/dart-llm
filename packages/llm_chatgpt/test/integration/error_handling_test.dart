/// Integration tests for Error Handling
///
/// Part of the comprehensive ChatGPT integration test suite.
///
/// Requires API key to be set via OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN environment variable.
library;

import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('ChatGPT Integration Tests - Error Handling', () {
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

    group('Error Handling Tests', () {
      test(
        'invalid model name',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          await expectLater(
            repo.streamChat(chatModel, messages: []),
            emitsError(isA<LLMApiException>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'invalid API key',
        () async {
          final badRepo = createRepository(customApiKey: 'invalid-key-12345');
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          await expectLater(
            badRepo.streamChat(chatModel, messages: messages),
            emitsError(isA<LLMApiException>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'invalid base URL',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final badRepo = createRepository(
            customBaseUrl: 'https://invalid-host-12345.com',
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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          // Make rapid requests to potentially trigger rate limiting
          final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

          // Make multiple rapid requests
          final futures = List.generate(10, (_) {
            return repo.streamChat(chatModel, messages: messages).toList();
          });

          // At least some should succeed, but rate limiting might occur
          final results = await Future.wait(futures, eagerError: false);
          expect(results.length, equals(10));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
