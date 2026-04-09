/// Integration tests for Embeddings (unsupported)
///
/// Part of the comprehensive Claude integration test suite.
///
/// Claude does not support embeddings. These tests verify that the correct
/// error is raised when embedding methods are called.
library;

import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Claude Integration Tests - Embeddings (Unsupported)', () {
    late ClaudeChatRepository repo;

    setUpAll(() {
      // ignore: avoid_print
      if (!hasApiKey()) {
        // ignore: avoid_print
        print('⚠️  API key not found. Set ANTHROPIC_API_KEY');
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

    group('Embedding Unsupported Tests', () {
      test(
        'embed throws UnsupportedError',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          await expectLater(
            repo.embed(model: chatModel, messages: ['Hello world']),
            throwsA(isA<UnsupportedError>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test(
        'batchEmbed throws UnsupportedError',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          await expectLater(
            repo.batchEmbed(
              model: chatModel,
              messages: ['Hello world', 'Goodbye world'],
            ),
            throwsA(isA<UnsupportedError>()),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 10)),
      );
    });
  });
}
