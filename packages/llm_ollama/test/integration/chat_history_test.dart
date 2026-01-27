/// Integration tests for Chat History
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Chat History', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Chat History Tests', () {
      test(
        'two-turn conversation',
        () async {
          final messages1 = [
            LLMMessage(role: LLMRole.user, content: 'My name is Alice.'),
          ];

          final chunks1 = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages1),
            const Duration(seconds: 90),
          );
          expect(chunks1, isNotEmpty);

          final messages2 = [
            ...messages1,
            LLMMessage(
              role: LLMRole.assistant,
              content: extractContent(chunks1),
            ),
            LLMMessage(role: LLMRole.user, content: 'What is my name?'),
          ];

          final chunks2 = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages2),
            const Duration(seconds: 90),
          );

          final response2 = extractContent(chunks2).toLowerCase();
          expect(
            response2.contains('alice') || response2.contains('alice'),
            isTrue,
            reason: 'Model should remember the name from previous turn',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'three-turn conversation',
        () async {
          final messages = [
            LLMMessage(role: LLMRole.user, content: 'I like apples.'),
          ];

          // Turn 1
          var chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );
          messages.add(
            LLMMessage(
              role: LLMRole.assistant,
              content: extractContent(chunks),
            ),
          );

          // Turn 2
          messages.add(
            LLMMessage(role: LLMRole.user, content: 'What fruit do I like?'),
          );
          chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );
          messages.add(
            LLMMessage(
              role: LLMRole.assistant,
              content: extractContent(chunks),
            ),
          );

          // Turn 3
          messages.add(
            LLMMessage(role: LLMRole.user, content: 'Do I like oranges?'),
          );
          chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'context preservation across multiple turns',
        () async {
          final messages = [
            LLMMessage(role: LLMRole.user, content: 'Remember this number: 42'),
          ];

          // Turn 1
          var chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );
          messages.add(
            LLMMessage(
              role: LLMRole.assistant,
              content: extractContent(chunks),
            ),
          );

          // Turn 2 - ask about the number
          messages.add(
            LLMMessage(
              role: LLMRole.user,
              content: 'What number did I ask you to remember?',
            ),
          );
          chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          final response = extractContent(chunks).toLowerCase();
          expect(
            response.contains('42'),
            isTrue,
            reason: 'Model should remember the number from context',
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'mixed roles in conversation',
        () async {
          final messages = [
            LLMMessage(role: LLMRole.system, content: 'You are a math tutor.'),
            LLMMessage(role: LLMRole.user, content: 'What is 5 + 3?'),
          ];

          final chunks1 = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          final messages2 = [
            ...messages,
            LLMMessage(
              role: LLMRole.assistant,
              content: extractContent(chunks1),
            ),
            LLMMessage(role: LLMRole.user, content: 'Now multiply that by 2'),
          ];

          final chunks2 = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages2),
            const Duration(seconds: 90),
          );

          expect(chunks2, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'long conversation history',
        () async {
          final messages = <LLMMessage>[];
          for (int i = 1; i <= 5; i++) {
            messages.add(LLMMessage(role: LLMRole.user, content: 'Message $i'));
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(chatModel, messages: messages),
              const Duration(seconds: 90),
            );
            messages.add(
              LLMMessage(
                role: LLMRole.assistant,
                content: extractContent(chunks),
              ),
            );
          }

          // Final message that references earlier context
          messages.add(
            LLMMessage(role: LLMRole.user, content: 'What was message 3?'),
          );
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(chatModel, messages: messages),
            const Duration(seconds: 90),
          );

          expect(chunks, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 10)),
      );
    });
  });
}
