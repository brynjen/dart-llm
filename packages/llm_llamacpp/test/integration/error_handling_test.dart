// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for error handling functionality.
void main() {
  final config = TestConfig.instance;

  group('Error Handling', () {
    late LlamaCppChatRepository repo;
    bool libraryAvailable = false;

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 512,
        batchSize: 128,
        nGpuLayers: config.gpuLayers,
      );

      // Try to initialize backend to check if library is available
      try {
        repo.initializeBackend();
        libraryAvailable = true;
      } catch (e) {
        libraryAvailable = false;
      }
    });

    tearDown(() {
      repo.dispose();
    });

    test('throws on invalid model path', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      expect(
        () => repo.loadModel('/nonexistent/path/model.gguf'),
        throwsA(anything),
      );
    });

    test('throws on invalid file format', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      // Create a temporary invalid file
      final tempFile = File('/tmp/invalid_model_test.gguf');
      tempFile.writeAsBytesSync([0, 1, 2, 3]); // Not a valid GGUF

      try {
        expect(() => repo.loadModel(tempFile.path), throwsA(anything));
      } finally {
        tempFile.deleteSync();
      }
    });

    test('throws when streaming without model', () async {
      // Don't load a model
      expect(() async {
        await for (final _ in repo.streamChat(
          'test',
          messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        )) {}
      }, throwsA(isA<ModelLoadException>()));
    });

    test('throws when embedding without model', () async {
      // Don't load a model
      expect(() async {
        await repo.embed(model: 'test', messages: ['Hello']);
      }, throwsA(isA<ModelLoadException>()));
    });

    test('throws on empty messages array', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath);

      await expectLater(
        repo.streamChat('test', messages: []),
        emitsError(isA<LLMApiException>()),
      );
    });

    test('handles unload errors gracefully', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath);
      expect(repo.isModelLoaded, isTrue);

      // Unload should work
      repo.unloadModel();
      expect(repo.isModelLoaded, isFalse);

      // Unloading again should be safe
      repo.unloadModel();
      expect(repo.isModelLoaded, isFalse);
    });

    test('handles dispose when model not loaded', () {
      // Should not throw when disposing without a model
      expect(() => repo.dispose(), returnsNormally);
    });

    test('handles dispose when model is loaded', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath);
      expect(repo.isModelLoaded, isTrue);

      // Dispose should work
      expect(() => repo.dispose(), returnsNormally);
    });

    test('handles invalid context size', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      // Create repo with very small context size
      final smallRepo = LlamaCppChatRepository(
        contextSize: 64, // Very small
        nGpuLayers: config.gpuLayers,
      );

      try {
        await smallRepo.loadModel(modelPath);
        // Model should still load, but may have issues with long prompts
        expect(smallRepo.isModelLoaded, isTrue);
      } finally {
        smallRepo.dispose();
      }
    });

    test('handles concurrent model loads', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      // Try to load model multiple times concurrently
      final futures = List.generate(3, (_) => repo.loadModel(modelPath));
      await Future.wait(futures);

      expect(repo.isModelLoaded, isTrue);
    });

    test('handles embedding with empty messages', () async {
      if (!libraryAvailable) {
        markTestSkipped('Library not available');
        return;
      }

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath);

      expect(() async {
        await repo.embed(model: 'test', messages: []);
      }, throwsA(isA<LLMApiException>()));
    });
  });
}
