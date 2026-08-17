/// Live verification of `thinking_token_budget` / `reasoning_effort` against
/// a vLLM server running a thinking model (Qwen3-family) with
/// `--reasoning-parser`.
///
/// These tests assert *behavior*, not just status codes: that the budget
/// actually bounds thinking length, that the budget wins over effort, and
/// that `think: false` / `ReasoningEffort.none` genuinely suppress thinking.
/// Token counts are estimated from text length (~4 chars/token), so bounds
/// are deliberately generous.
library;

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A prompt that reliably induces long thinking when unbudgeted.
const _thinkHardPrompt =
    'Prove step by step, very carefully, that the sum of the first n odd '
    'numbers equals n squared. Consider multiple approaches before answering.';

int _estimateTokens(String text) => (text.length / 4).ceil();

Future<({String thinking, String content})> _run(
  VLLMChatRepository repo,
  LLMChatOptions options, {
  String prompt = _thinkHardPrompt,
}) async {
  final chunks = await collectStreamWithTimeout(
    repo.streamChat(
      chatModel,
      messages: [LLMMessage(role: LLMRole.user, content: prompt)],
      options: options,
    ),
    const Duration(minutes: 3),
  );
  return (thinking: extractThinking(chunks), content: extractContent(chunks));
}

void main() {
  group(
    'VLLM Integration Tests - Thinking Budget (live behavior)',
    () {
      late VLLMChatRepository repo;

      setUp(() {
        repo = createRepository();
      });

      test(
        'a small budget hard-bounds thinking that would otherwise run long',
        () async {
          final unbudgeted = await _run(
            repo,
            const LLMChatOptions(think: true, maxOutputTokens: 3000),
          );
          final budgeted = await _run(
            repo,
            const LLMChatOptions(
              think: true,
              reasoningBudget: 128,
              maxOutputTokens: 3000,
            ),
          );

          expect(budgeted.thinking, isNotEmpty);
          expect(budgeted.content, isNotEmpty);

          final unbudgetedTokens = _estimateTokens(unbudgeted.thinking);
          final budgetedTokens = _estimateTokens(budgeted.thinking);

          // The unbudgeted run must think substantially (else this test
          // proves nothing) and the budgeted run must be cut well below it,
          // near the requested 128 tokens (3x fudge for estimation error).
          expect(
            unbudgetedTokens,
            greaterThan(400),
            reason: 'unbudgeted thinking should run long on this prompt',
          );
          expect(
            budgetedTokens,
            lessThanOrEqualTo(128 * 3),
            reason: 'budget 128 should hard-cap thinking',
          );
          expect(budgetedTokens, lessThan(unbudgetedTokens));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 6)),
      );

      test(
        'a larger budget allows proportionally more thinking',
        () async {
          final small = await _run(
            repo,
            const LLMChatOptions(
              think: true,
              reasoningBudget: 128,
              maxOutputTokens: 3000,
            ),
          );
          final large = await _run(
            repo,
            const LLMChatOptions(
              think: true,
              reasoningBudget: 1024,
              maxOutputTokens: 4000,
            ),
          );

          expect(
            _estimateTokens(large.thinking),
            greaterThan(_estimateTokens(small.thinking)),
            reason: 'budget 1024 should permit more thinking than 128',
          );
          expect(
            _estimateTokens(large.thinking),
            lessThanOrEqualTo(1024 * 3),
            reason: 'budget 1024 should still cap thinking',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 6)),
      );

      test(
        'budget wins over effort (budget-native precedence)',
        () async {
          final result = await _run(
            repo,
            const LLMChatOptions(
              think: true,
              reasoningBudget: 128,
              reasoningEffort: ReasoningEffort.max,
              maxOutputTokens: 3000,
            ),
          );
          expect(
            _estimateTokens(result.thinking),
            lessThanOrEqualTo(128 * 3),
            reason: 'effort max must not undo the 128-token budget',
          );
          expect(result.content, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 4)),
      );

      test(
        'think:false suppresses thinking entirely',
        () async {
          final result = await _run(
            repo,
            const LLMChatOptions(think: false, maxOutputTokens: 1500),
            prompt: 'What is 12 * 12?',
          );
          expect(result.thinking, isEmpty);
          expect(result.content, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'ReasoningEffort.none suppresses thinking even with think:true',
        () async {
          final result = await _run(
            repo,
            const LLMChatOptions(
              think: true,
              reasoningEffort: ReasoningEffort.none,
              maxOutputTokens: 1500,
            ),
            prompt: 'What is 12 * 12?',
          );
          expect(result.thinking, isEmpty);
          expect(result.content, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'reasoning_effort levels are accepted and thinking streams separately',
        () async {
          for (final effort in [ReasoningEffort.low, ReasoningEffort.high]) {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Briefly: why is the sky blue?',
                  ),
                ],
                options: LLMChatOptions(
                  think: true,
                  reasoningEffort: effort,
                  maxOutputTokens: 2500,
                ),
              ),
              const Duration(minutes: 3),
            );
            final thinkingChunks = chunks
                .where((c) => (c.message?.thinking ?? '').isNotEmpty)
                .length;
            expect(
              thinkingChunks,
              greaterThan(1),
              reason:
                  '$effort: thinking should stream as separate deltas '
                  '(reasoning parser active)',
            );
            expect(extractContent(chunks), isNotEmpty, reason: '$effort');
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 7)),
      );
    },
    skip: reasoningTestsEnabled
        ? false
        : 'Set VLLM_ENABLE_REASONING_TESTS=true',
  );
}
