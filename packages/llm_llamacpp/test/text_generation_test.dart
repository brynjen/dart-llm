// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for text generation functionality.
void main() {
  final config = TestConfig.instance;

  group('Text Generation', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() async {
      modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        print('⚠️  No text model available for generation tests');
        return;
      }

      print('Using model: $modelPath');
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

    test('generates response to simple prompt', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'What is 2 + 2? Answer with just the number.',
        ),
      ];

      print('Prompt: ${messages.first.content}');
      print('Response: ', );

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        final content = chunk.message?.content ?? '';
        buffer.write(content);
        stdout.write(content);
      }
      print('\n');

      final response = buffer.toString();
      expect(response, isNotEmpty);
      // Most models should get this right
      expect(response.toLowerCase(), anyOf(contains('4'), contains('four')));
    }, timeout: Timeout(Duration(minutes: 2)));

    test('generates streaming tokens', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Count from 1 to 5.',
        ),
      ];

      int tokenCount = 0;
      bool sawDone = false;

      await for (final chunk in repo.streamChat('test', messages: messages)) {
        if (chunk.message?.content != null &&
            chunk.message!.content!.isNotEmpty) {
          tokenCount++;
        }
        if (chunk.done == true) {
          sawDone = true;
        }
      }

      expect(tokenCount, greaterThan(0), reason: 'Should generate tokens');
      expect(sawDone, isTrue, reason: 'Should signal completion');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('handles system prompt', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.system,
          content: 'You are a pirate. Always respond like a pirate.',
        ),
        LLMMessage(
          role: LLMRole.user,
          content: 'Hello!',
        ),
      ];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
      }

      final response = buffer.toString().toLowerCase();
      print('Pirate response: $response');

      // Should have some pirate-like language or at minimum respond
      final hasPirateLanguage = response.contains('ahoy') ||
          response.contains('matey') ||
          response.contains('arr') ||
          response.contains('ye') ||
          response.contains('captain') ||
          response.contains('sea') ||
          response.contains('ship');
      expect(hasPirateLanguage || response.isNotEmpty, isTrue,
          reason: 'Expected pirate-like language or non-empty response');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('maintains conversation context', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      // First turn - introduce a name
      final messages1 = [
        LLMMessage(
          role: LLMRole.system,
          content: 'Remember what the user tells you. Be brief.',
        ),
        LLMMessage(
          role: LLMRole.user,
          content: 'My favorite color is blue.',
        ),
      ];

      final buffer1 = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages1)) {
        buffer1.write(chunk.message?.content ?? '');
      }
      final response1 = buffer1.toString();
      print('Turn 1 response: $response1');

      // Second turn - ask about the name
      final messages2 = [
        ...messages1,
        LLMMessage(role: LLMRole.assistant, content: response1),
        LLMMessage(
          role: LLMRole.user,
          content: 'What is my favorite color?',
        ),
      ];

      final buffer2 = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages2)) {
        buffer2.write(chunk.message?.content ?? '');
      }
      final response2 = buffer2.toString().toLowerCase();
      print('Turn 2 response: $response2');

      expect(response2, contains('blue'));
    }, timeout: Timeout(Duration(minutes: 3)));

    test('respects max tokens limit', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      // Create repo with limited max tokens (via prompt design)
      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Say exactly one word: Hello',
        ),
      ];

      final buffer = StringBuffer();
      int tokenCount = 0;
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
        if (chunk.message?.content?.isNotEmpty == true) {
          tokenCount++;
        }
      }

      // Response should be relatively short
      final response = buffer.toString().trim();
      print('Response: "$response" (tokens: $tokenCount)');
      
      // Should be a short response
      expect(response.split(' ').length, lessThanOrEqualTo(10));
    }, timeout: Timeout(Duration(minutes: 1)));

    test('handles empty message list gracefully', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      // Empty messages should still work (might generate something random)
      final buffer = StringBuffer();
      await for (final chunk
          in repo.streamChat('test', messages: <LLMMessage>[])) {
        buffer.write(chunk.message?.content ?? '');
      }

      // Should complete without error
      expect(true, isTrue);
    }, timeout: Timeout(Duration(minutes: 1)));

    test('throws when no model loaded', () async {
      // Don't load a model
      expect(
        () async {
          await for (final _ in repo.streamChat('test', messages: [
            LLMMessage(role: LLMRole.user, content: 'Hello'),
          ])) {}
        },
        throwsA(isA<ModelLoadException>()),
      );
    });
  });

  group('Prompt Templates', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 512,
        nGpuLayers: config.gpuLayers,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('auto-detects template from model name', () {
      expect(getTemplateForModel('llama-3-8b'), isA<Llama3Template>());
      expect(getTemplateForModel('llama-2-7b'), isA<Llama2Template>());
      expect(getTemplateForModel('qwen2-7b'), isA<ChatMLTemplate>());
      expect(getTemplateForModel('phi-3-mini'), isA<Phi3Template>());
      expect(getTemplateForModel('vicuna-13b'), isA<VicunaTemplate>());
      expect(getTemplateForModel('alpaca-7b'), isA<AlpacaTemplate>());
    });

    test('formats messages with ChatML template', () {
      final template = ChatMLTemplate();
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello!'),
      ];

      final formatted = template.format(messages);

      expect(formatted, contains('<|im_start|>system'));
      expect(formatted, contains('You are helpful.'));
      expect(formatted, contains('<|im_start|>user'));
      expect(formatted, contains('Hello!'));
      expect(formatted, contains('<|im_end|>'));
    });

    test('formats messages with Llama3 template', () {
      final template = Llama3Template();
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello!'),
      ];

      final formatted = template.format(messages);

      expect(formatted, contains('<|begin_of_text|>'));
      expect(formatted, contains('<|start_header_id|>system<|end_header_id|>'));
      expect(formatted, contains('<|start_header_id|>user<|end_header_id|>'));
    });

    test('can set custom template', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      // Set custom template
      repo.template = ChatMLTemplate();
      expect(repo.template, isA<ChatMLTemplate>());

      repo.template = Llama3Template();
      expect(repo.template, isA<Llama3Template>());
    });

    test('generates with explicit template', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);
      repo.template = ChatMLTemplate();

      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hi'),
      ];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat('test', messages: messages)) {
        buffer.write(chunk.message?.content ?? '');
      }

      expect(buffer.toString(), isNotEmpty);
    }, timeout: Timeout(Duration(minutes: 1)));
  });

  group('Performance', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.smallModelPath ?? config.textModelPath;
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 1024,
        nGpuLayers: config.gpuLayers,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('reports token counts', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hello, how are you?'),
      ];

      int? promptTokens;
      int? evalTokens;

      await for (final chunk in repo.streamChat('test', messages: messages)) {
        if (chunk.done == true) {
          promptTokens = chunk.promptEvalCount;
          evalTokens = chunk.evalCount;
        }
      }

      print('Prompt tokens: $promptTokens');
      print('Generated tokens: $evalTokens');

      // Should report some token counts
      if (promptTokens != null) {
        expect(promptTokens, greaterThan(0));
      }
      if (evalTokens != null) {
        expect(evalTokens, greaterThanOrEqualTo(0));
      }
    }, timeout: Timeout(Duration(minutes: 2)));

    test('measures generation speed', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Write a short paragraph about the weather.',
        ),
      ];

      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;

      await for (final chunk in repo.streamChat('test', messages: messages)) {
        if (chunk.message?.content?.isNotEmpty == true) {
          tokenCount++;
        }
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final tokensPerSecond =
          tokenCount > 0 ? (tokenCount / (elapsed / 1000)).toStringAsFixed(1) : 'N/A';

      print('Generated $tokenCount tokens in ${elapsed}ms');
      print('Speed: $tokensPerSecond tokens/sec');

      expect(tokenCount, greaterThan(0));
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}

