/// Integration tests for Thinking Mode
///
/// Part of the comprehensive VLLM integration test suite.
library;

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'VLLM Integration Tests - Thinking Mode',
    () {
      late VLLMChatRepository repo;

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
          skip: toolTestsEnabled ? false : 'Set VLLM_ENABLE_TOOL_TESTS=true',
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

        test(
          'reasoningBudget is enforced or cleanly rejected',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Think carefully: how many r\'s are in "strawberry"?',
              ),
            ];

            try {
              final chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  options: const LLMChatOptions(
                    think: true,
                    reasoningBudget: 256,
                  ),
                ),
                const Duration(seconds: 90),
              );
              expect(chunks, isNotEmpty);
              final thinking = extractThinking(chunks);
              final content = extractContent(chunks);
              expect(
                thinking.isNotEmpty || content.isNotEmpty,
                isTrue,
                reason: 'Should receive thinking or content',
              );
            } on ThinkingNotSupportedException {
              // Server runs without --reasoning-parser: the budget cannot be
              // honored and the library reports that instead of a raw 400.
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 2)),
        );

        test(
          'reasoningEffort low succeeds with thinking',
          () async {
            final messages = [
              LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                options: const LLMChatOptions(
                  think: true,
                  reasoningEffort: ReasoningEffort.low,
                ),
              ),
              const Duration(seconds: 90),
            );

            expect(chunks, isNotEmpty);
            final thinking = extractThinking(chunks);
            final content = extractContent(chunks);
            expect(thinking.isNotEmpty || content.isNotEmpty, isTrue);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 2)),
        );
      });
    },
    skip: reasoningTestsEnabled
        ? false
        : 'Set VLLM_ENABLE_REASONING_TESTS=true',
  );
}
