/// Integration tests for Thinking Mode
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Thinking Mode', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Thinking Mode Tests', () {
      test(
        'thinking mode enabled',
        () async {
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Think about what 2+2 equals, then tell me.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages, think: true),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
          final thinking = extractThinking(chunks);
          final content = extractContent(chunks);

          // Should have either thinking or content
          expect(
            thinking.isNotEmpty || content.isNotEmpty,
            isTrue,
            reason: 'Should receive thinking or content',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'thinking with tools',
        () async {
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Think about calculating 10 * 5, then use the calculator.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: messages,
              tools: [CalculatorTool()],
              think: true,
            ),
            const Duration(minutes: 3),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'thinking content structure',
        () async {
          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Think step by step about why the sky is blue.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages, think: true),
            const Duration(seconds: 90),
          );

          final thinking = extractThinking(chunks);
          final content = extractContent(chunks);
          // If thinking mode works, we should get thinking content
          // (though model may not always produce it)
          expect(chunks, isNotEmpty);
          // Verify we got either thinking or content
          expect(thinking.isNotEmpty || content.isNotEmpty, isTrue);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
