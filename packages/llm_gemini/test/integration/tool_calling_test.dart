/// Integration tests for Tool Calling
///
/// Part of the comprehensive Gemini integration test suite.
///
/// Requires API key to be set via GEMINI_API_KEY environment variable.
library;

import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Gemini Integration Tests - Tool Calling', () {
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

    group('Streaming progress', () {
      test(
        'reports the tool name before the call completes',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          // The delta channel exists so a caller learns which tool is running
          // without waiting for its arguments. Assert ordering against the
          // real wire, and that the completed call is still whole.
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
                content: 'Use the calculator tool to work out 15 * 7.',
              ),
            ],
            tools: [CalculatorTool()],
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

          expect(streamedName, 'calculator');
          expect(
            nameSeenBeforeFinish,
            isTrue,
            reason: 'the tool name must arrive before the finish reason',
          );

          expect(completed, isNotNull);
          expect(completed!.name, 'calculator');
          // Fragments are the same bytes as the completed call, not a summary.
          expect(fragments.toString(), completed.arguments);
          expect(completed.argumentsJson['expression'], isNotNull);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('Tool Calling Tests', () {
      test(
        'simple tool execution with calculator',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
        'manual tool-call exposure when auto execution is disabled',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Use the calculator tool to calculate 8 * 9.',
                ),
              ],
              options: LLMChatOptions(
                tools: [CalculatorTool()],
                autoExecuteTools: false,
              ),
            ),
            const Duration(minutes: 3),
          );

          final toolCalls = chunks
              .expand((chunk) => chunk.message?.toolCalls ?? const [])
              .toList();
          expect(toolCalls, isNotEmpty);
          expect(
            chunks.where((chunk) => chunk.message?.role == LLMRole.tool),
            isEmpty,
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'tool with optional parameters',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
        'max tool attempts limit',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Keep calculating 1+1 repeatedly.',
            ),
          ];

          // Two lawful outcomes, and which one happens is up to the model:
          // it either stops calling tools and answers (stream completes), or
          // it keeps calling and the budget runs out (the loop refuses to
          // return a truncated conversation and throws). Asserting only "some
          // chunks arrived" made this pass or fail on model temperament — it
          // failed against Gemini and passed elsewhere purely by luck.
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
                  "not the deepest frame's empty budget",
            );
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'tool execution error handling',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Use the error_tool to test error handling.',
            ),
          ];

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: messages,
              tools: [ErrorTool()],
            ),
            const Duration(minutes: 3),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'tool with async operations',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final messages = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Use the slow_tool with a 1 second delay.',
            ),
          ];

          final stopwatch = Stopwatch()..start();
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages, tools: [SlowTool()]),
            const Duration(minutes: 3),
          );
          stopwatch.stop();

          expect(chunks, isNotEmpty);
          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1000));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  });
}
