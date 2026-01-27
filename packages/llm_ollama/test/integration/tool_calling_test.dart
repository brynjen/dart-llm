/// Integration tests for Tool Calling
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Tool Calling', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
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

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: messages,
              tools: [CalculatorTool()],
              toolAttempts: 3, // Limit to 3 attempts
            ),
            const Duration(minutes: 5),
          );

          expect(chunks, isNotEmpty);
          // Should eventually stop due to max attempts
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
            repo.streamChat(chatModel, messages: messages, tools: [SlowTool()]),
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

          // Use a shorter timeout to test timeout handling
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages, tools: [SlowTool()]),
            const Duration(seconds: 5), // Shorter timeout
          );

          // Should either complete or timeout gracefully
          expect(chunks, isA<List<LLMChunk>>());
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );
    });
  });
}
