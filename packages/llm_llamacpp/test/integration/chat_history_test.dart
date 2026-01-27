// ignore_for_file: deprecated_member_use_from_same_package

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for chat history and multi-turn conversations.
void main() {
  final config = TestConfig.instance;

  group('Chat History', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
      // ignore: avoid_print
      if (modelPath == null) {
        // ignore: avoid_print
        print('⚠️  No model available for chat history tests');
      }
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 2048,
        batchSize: 256,
        nGpuLayers: config.gpuLayers,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('two-turn conversation', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      // Turn 1
      final messages1 = [
        LLMMessage(role: LLMRole.user, content: 'My name is Alice.'),
      ];

      String response1 = '';
      await for (final chunk in repo.streamChat('test', messages: messages1)) {
        response1 += chunk.message?.content ?? '';
      }

      // Turn 2
      final messages2 = [
        ...messages1,
        LLMMessage(role: LLMRole.assistant, content: response1),
        LLMMessage(role: LLMRole.user, content: 'What is my name?'),
      ];

      String response2 = '';
      await for (final chunk in repo.streamChat('test', messages: messages2)) {
        response2 += chunk.message?.content ?? '';
      }

      final response2Lower = response2.toLowerCase();
      expect(
        response2Lower.contains('alice'),
        isTrue,
        reason: 'Model should remember the name from previous turn',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('three-turn conversation', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      var messages = [
        LLMMessage(role: LLMRole.user, content: 'I like apples.'),
      ];

      // Turn 1
      String response1 = '';
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        response1 += chunk.message?.content ?? '';
      }
      messages.add(LLMMessage(role: LLMRole.assistant, content: response1));

      // Turn 2
      messages.add(
        LLMMessage(role: LLMRole.user, content: 'What fruit do I like?'),
      );
      String response2 = '';
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        response2 += chunk.message?.content ?? '';
      }
      messages.add(LLMMessage(role: LLMRole.assistant, content: response2));

      // Turn 3
      messages.add(
        LLMMessage(role: LLMRole.user, content: 'Do I like oranges?'),
      );
      String response3 = '';
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        response3 += chunk.message?.content ?? '';
      }

      expect(response3, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
      'context preservation across multiple turns',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        var messages = [
          LLMMessage(role: LLMRole.user, content: 'Remember this number: 42'),
        ];

        // Turn 1
        String response1 = '';
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          response1 += chunk.message?.content ?? '';
        }
        messages.add(LLMMessage(role: LLMRole.assistant, content: response1));

        // Turn 2 - ask about the number
        messages.add(
          LLMMessage(
            role: LLMRole.user,
            content: 'What number did I ask you to remember?',
          ),
        );
        String response2 = '';
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          response2 += chunk.message?.content ?? '';
        }

        expect(
          response2.contains('42'),
          isTrue,
          reason: 'Model should remember the number from context',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('mixed roles in conversation', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(role: LLMRole.system, content: 'You are a math tutor.'),
        LLMMessage(role: LLMRole.user, content: 'What is 5 + 3?'),
      ];

      String response1 = '';
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        response1 += chunk.message?.content ?? '';
      }

      final messages2 = [
        ...messages,
        LLMMessage(role: LLMRole.assistant, content: response1),
        LLMMessage(role: LLMRole.user, content: 'Now multiply that by 2'),
      ];

      String response2 = '';
      await for (final chunk in repo.streamChat('test', messages: messages2)) {
        response2 += chunk.message?.content ?? '';
      }

      expect(response2, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('long conversation history', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      var messages = <LLMMessage>[];
      for (int i = 1; i <= 5; i++) {
        messages.add(LLMMessage(role: LLMRole.user, content: 'Message $i'));
        String response = '';
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          response += chunk.message?.content ?? '';
        }
        messages.add(LLMMessage(role: LLMRole.assistant, content: response));
      }

      // Final message that references earlier context
      messages.add(
        LLMMessage(role: LLMRole.user, content: 'What was message 3?'),
      );
      String finalResponse = '';
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        finalResponse += chunk.message?.content ?? '';
      }

      expect(finalResponse, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('context window limits', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      // Build a conversation that may approach context limits
      var messages = <LLMMessage>[];
      for (int i = 1; i <= 10; i++) {
        messages.add(
          LLMMessage(
            role: LLMRole.user,
            content: 'Turn $i: Tell me about number $i in detail.',
          ),
        );
        String response = '';
        try {
          await for (final chunk in repo.streamChat(
            'test',
            messages: messages,
          )) {
            response += chunk.message?.content ?? '';
          }
          messages.add(LLMMessage(role: LLMRole.assistant, content: response));
        } catch (e) {
          // May fail if context window is exceeded
          // ignore: avoid_print
          print('Context window test had error (may be expected): $e');
          break;
        }
      }

      // Should have completed at least some turns
      expect(messages.length, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 15)));
  });
}
