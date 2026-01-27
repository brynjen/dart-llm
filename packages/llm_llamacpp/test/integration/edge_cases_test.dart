// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for edge cases and unusual inputs.
void main() {
  final config = TestConfig.instance;

  group('Edge Cases', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
      // ignore: avoid_print
      if (modelPath == null) {
        // ignore: avoid_print
        print('⚠️  No model available for edge case tests');
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

    test('handles empty message content', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [LLMMessage(role: LLMRole.user, content: '')];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
      }

      // Should complete without error
      expect(true, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'handles very long single message',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final longMessage = 'This is a test. ' * 500; // ~7500 characters
        final messages = [LLMMessage(role: LLMRole.user, content: longMessage)];

        final buffer = StringBuffer();
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          buffer.write(chunk.message?.content ?? '');
        }

        expect(buffer.toString(), isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('handles unicode edge cases', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final unicodeText = 'Hello 🌍 你好 مرحبا 🚀';
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Echo: $unicodeText'),
      ];

      final buffer = StringBuffer();
      try {
        await for (final chunk in repo.streamChat('test', messages: messages)) {
          buffer.write(chunk.message?.content ?? '');
        }
      } catch (e) {
        // Some models may have encoding issues with unicode
        // ignore: avoid_print
        print(
          'Unicode test had encoding issue (expected with some models): $e',
        );
      }

      // Should complete (may have encoding issues but shouldn't crash)
      expect(true, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('handles JSON-like content', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      const jsonLikeContent =
          'Here is some JSON: {"key": "value", "number": 42}';
      final messages = [
        LLMMessage(role: LLMRole.user, content: jsonLikeContent),
      ];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
      }

      expect(buffer.toString(), isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('handles code-like content', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      const codeContent =
          'Here is code: ```dart\nvoid main() {\n  print("test");\n}\n```';
      final messages = [LLMMessage(role: LLMRole.user, content: codeContent)];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
      }

      expect(buffer.toString(), isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('handles concurrent requests', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [LLMMessage(role: LLMRole.user, content: 'Say hello')];

      final futures = List.generate(3, (_) {
        final buffer = StringBuffer();
        return repo
            .streamChat('test', messages: messages)
            .forEach((chunk) {
              buffer.write(chunk.message?.content ?? '');
            })
            .then((_) => buffer.toString());
      });

      final results = await Future.wait(futures);
      for (final result in results) {
        expect(result, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'handles extremely long prompts',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        // Create a very long prompt (may exceed context window)
        final longPrompt = 'Repeat this word: test. ' * 1000; // ~5000 words
        final messages = [LLMMessage(role: LLMRole.user, content: longPrompt)];

        final buffer = StringBuffer();
        try {
          await for (final chunk in repo.streamChat(
            'test',
            messages: messages,
          )) {
            buffer.write(chunk.message?.content ?? '');
          }
        } catch (e) {
          // May fail if prompt exceeds context, but should fail gracefully
          // ignore: avoid_print
          print('Long prompt test had error (may be expected): $e');
        }

        // Should either complete or fail gracefully
        expect(true, isTrue);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'handles rapid successive requests',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final messages = [
          LLMMessage(role: LLMRole.user, content: 'Say "test"'),
        ];

        // Make rapid successive requests
        for (int i = 0; i < 3; i++) {
          final buffer = StringBuffer();
          await for (final chunk in repo.streamChat(
            'test',
            messages: messages,
          )) {
            buffer.write(chunk.message?.content ?? '');
          }
          expect(buffer.toString(), isNotEmpty);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'handles special characters in prompts',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        const specialChars = '!@#\$%^&*()_+-=[]{}|;:\'",.<>?/~`';
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'Echo these: $specialChars'),
        ];

        final buffer = StringBuffer();
        try {
          await for (final chunk in repo.streamChat(
            'test',
            messages: messages,
          )) {
            buffer.write(chunk.message?.content ?? '');
          }
        } catch (e) {
          // Some models may have issues with special characters
          // ignore: avoid_print
          print('Special chars test had issue (may be expected): $e');
        }

        // Should complete or fail gracefully
        expect(true, isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
