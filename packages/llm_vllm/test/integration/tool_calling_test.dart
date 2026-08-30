/// Integration tests for Tool Calling
///
/// Part of the comprehensive VLLM integration test suite.
library;

import 'dart:async';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'VLLM Integration Tests - Tool Calling',
    () {
      late VLLMChatRepository repo;

      setUp(() {
        repo = createRepository();
      });

      group('Streaming progress', () {
        test(
          'reports the tool name before the call completes',
          () async {
            // The whole point of the delta channel: the name is on the wire in
            // the first tool-call event, and used to be withheld until the
            // last. Run this more than once when changing the converter — vLLM
            // picks nondeterministically between ending the stream with a lone
            // finish_reason chunk and fusing it onto the final fragment.
            var sawFinish = false;
            var nameSeenBeforeFinish = false;
            String? streamedName;
            final fragments = StringBuffer();
            LLMToolCall? completed;

            await for (final chunk in repo.streamChat(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'What is the weather in Oslo? Use get_weather.',
                ),
              ],
              tools: [WeatherTool()],
              options: const LLMChatOptions(autoExecuteTools: false),
            )) {
              for (final delta
                  in chunk.message?.toolCallDeltas ??
                      const <LLMToolCallDelta>[]) {
                if (delta.name != null) {
                  streamedName ??= delta.name;
                  if (!sawFinish) nameSeenBeforeFinish = true;
                }
                if (delta.argumentsDelta != null) {
                  fragments.write(delta.argumentsDelta);
                }
              }

              final calls = chunk.message?.toolCalls;
              if (calls != null && calls.isNotEmpty) completed = calls.first;
              if (chunk.finishReason != null) sawFinish = true;
            }

            expect(streamedName, 'get_weather');
            expect(
              nameSeenBeforeFinish,
              isTrue,
              reason: 'the tool name must arrive before the finish reason',
            );

            // The completed call is still whole and executable, and the
            // fragments are genuinely the same bytes rather than a summary.
            expect(completed, isNotNull);
            expect(completed!.name, 'get_weather');
            expect(fragments.toString(), completed.arguments);
            expect(completed.argumentsJson['location'], isNotNull);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 3)),
        );

        test(
          'sends extraHeaders without disturbing the response',
          () async {
            final tagged = createRepository(
              extraHeaders: const {'x-integration-probe': 'dart-llm'},
            );
            addTearDown(tagged.close);

            final chunks = await collectStreamWithTimeout(
              tagged.streamChat(
                chatModel,
                messages: [LLMMessage(role: LLMRole.user, content: 'Say OK.')],
              ),
              const Duration(minutes: 2),
            );

            expect(chunks, isNotEmpty);
            expect(extractContent(chunks), isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 2)),
        );
      });

      group('Tool Calling Tests', () {
        test(
          'simple tool execution with calculator',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Calculate 15 * 7 using the calculator tool.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
            final content = extractContent(chunks).toLowerCase();
            // Model should use the tool and get result
            expect(
              content.contains('105') || content.contains('calculator'),
              isTrue,
              reason: 'Should use calculator tool and get result',
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool with required parameters',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Get the weather for Paris using the weather tool.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [WeatherTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool with optional parameters',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Get weather for London in fahrenheit.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [WeatherTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool returning complex data',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Search for "machine learning" with limit 3.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [SearchTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'multiple tools available - model chooses correct one',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Calculate 10 + 20. Use the calculator tool.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [CalculatorTool(), WeatherTool(), SearchTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool with no parameters',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Get the current time using the time tool.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [NoParamTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool with nested object parameters',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Use complex_tool with config: items=["a","b"], enabled=true',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [ComplexTool()],
              ),
              const Duration(minutes: 3),
            );

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool chain - multiple tool calls in sequence',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'First calculate 5 * 6, then search for the result.',
              ),
            ];

            var chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [CalculatorTool(), SearchTool()],
              ),
              const Duration(minutes: 5),
            );

            // If model used calculator, add result and continue
            final content1 = extractContent(chunks);
            if (content1.contains('30') || content1.contains('calculator')) {
              messages.add(
                LLMMessage(role: LLMRole.assistant, content: content1),
              );
              messages.add(
                LLMMessage(role: LLMRole.user, content: 'Now search for "30"'),
              );

              chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  tools: [CalculatorTool(), SearchTool()],
                ),
                const Duration(minutes: 5),
              );
            }

            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 10)),
        );

        test(
          'max tool attempts limit',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Keep calculating 1+1 repeatedly.',
              ),
            ];

            // Two lawful outcomes, and which one happens is up to the model:
            // it either stops calling tools and answers (stream completes), or
            // it keeps calling and the budget runs out (the loop refuses to
            // return a truncated conversation and throws). Asserting only
            // "some chunks arrived" missed the second outcome entirely, which
            // is the one this test exists to cover.
            const budget = 3;
            try {
              final chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  tools: [CalculatorTool()],
                  toolAttempts: budget,
                ),
                const Duration(minutes: 5),
              );
              expect(chunks, isNotEmpty);
              expect(extractContent(chunks), isNotEmpty);
            } on ToolLoopIncompleteException catch (e) {
              expect(e.attemptsRemaining, 0);
              expect(
                e.attemptsUsed,
                budget,
                reason:
                    'the exception must report the rounds actually consumed, '
                    'not the deepest frame\'s empty budget',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool execution error handling',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Use the error_tool to test error handling.',
              ),
            ];

            // The tool will throw an error, but the repository should handle it gracefully
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [ErrorTool()],
              ),
              const Duration(minutes: 3),
            );

            // Should complete without crashing
            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool with async operations',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Use the slow_tool with a 1 second delay.',
              ),
            ];

            final stopwatch = Stopwatch()..start();
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [SlowTool()],
              ),
              const Duration(minutes: 3),
            );
            stopwatch.stop();

            expect(chunks, isNotEmpty);
            // Should take at least 1 second due to tool delay
            expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1000));
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool timeout scenarios',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Use the slow_tool with a 10 second delay.',
              ),
            ];

            // Use a shorter timeout - tool takes 10s so stream may not complete
            List<LLMChunk> chunks;
            try {
              chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  tools: [SlowTool()],
                ),
                const Duration(seconds: 5),
              );
            } on TimeoutException {
              // Expected when tool delay exceeds stream timeout
              return;
            }

            // If completed, verify we got chunks
            expect(chunks, isA<List<LLMChunk>>());
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 1)),
        );

        test(
          'tool calling does not fail with missing toolCallId',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'Use the calculator tool to compute 2 + 2.',
              ),
            ];

            Object? caughtError;
            List<LLMChunk> chunks = const [];

            try {
              chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  tools: [CalculatorTool()],
                ),
                const Duration(minutes: 3),
              );
            } catch (e) {
              caughtError = e;
            }

            // The stream should complete without raising the historical
            // validation error:
            //   LLMApiException: HTTP 400 - Message 2: Tool message must have toolCallId
            if (caughtError is LLMApiException &&
                caughtError.message.contains(
                  'Tool message must have toolCallId',
                )) {
              fail(
                'Tool calling failed due to missing toolCallId validation error: '
                '${caughtError.message}',
              );
            }

            // Verify that any tool calls emitted by VLLM are mapped to
            // LLMToolCall objects with non-null, non-empty ids. This ensures the
            // dto layer provides stable ids for llm_core to reuse as toolCallId.
            final hasAnyToolCalls = chunks.any(
              (chunk) => (chunk.message?.toolCalls ?? const []).isNotEmpty,
            );
            if (hasAnyToolCalls) {
              final hasMissingId = chunks.any(
                (chunk) =>
                    chunk.message?.toolCalls?.any(
                      (toolCall) => toolCall.id == null || toolCall.id!.isEmpty,
                    ) ??
                    false,
              );
              expect(
                hasMissingId,
                isFalse,
                reason:
                    'All VLLM tool_calls should produce LLMToolCall with non-empty id',
              );
            }
            expect(hasAnyToolCalls, isTrue);
            expect(chunks, isNotEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });
    },
    skip: toolTestsEnabled ? false : 'Set VLLM_ENABLE_TOOL_TESTS=true',
  );
}
