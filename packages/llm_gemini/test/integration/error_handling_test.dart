/// Integration tests for Error Handling
///
/// Part of the comprehensive Gemini integration test suite.
///
/// Requires API key to be set via GEMINI_API_KEY environment variable.
library;

import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Gemini Integration Tests - Error Handling', () {
    late GeminiChatRepository repo;

    setUpAll(() {
      // ignore: avoid_print
      if (!hasApiKey()) {
        // ignore: avoid_print
        print('⚠️  API key not found. Set GEMINI_API_KEY');
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
            emitsError(anything),
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

          await expectLater(
            timeoutRepo.streamChat(chatModel, messages: messages),
            emitsError(anything),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });
  });
}
