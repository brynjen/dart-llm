// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Tests for model loading functionality.
void main() {
  final config = TestConfig.instance;

  setUpAll(() {
    config.printConfig();
  });

  group('Model Loading', () {
    late LlamaCppChatRepository repo;

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 512,
        batchSize: 128,
        nGpuLayers: config.gpuLayers,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('initializes backend without model', () {
      repo.initializeBackend();
      expect(repo.isModelLoaded, isFalse);
      expect(repo.model, isNull);
    });

    test('loads valid GGUF model', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      print('Loading model: $modelPath');
      final stopwatch = Stopwatch()..start();

      await repo.loadModel(modelPath);

      print('Loaded in ${stopwatch.elapsedMilliseconds}ms');

      expect(repo.isModelLoaded, isTrue);
      expect(repo.model, isNotNull);
      expect(repo.model!.vocabSize, greaterThan(0));
      expect(repo.model!.contextSizeTrain, greaterThan(0));
      expect(repo.model!.embeddingSize, greaterThan(0));

      print('  Vocab size: ${repo.model!.vocabSize}');
      print('  Context size (train): ${repo.model!.contextSizeTrain}');
      print('  Embedding size: ${repo.model!.embeddingSize}');
      print('  BOS token: ${repo.model!.bosToken}');
      print('  EOS token: ${repo.model!.eosToken}');
    });

    test('loads model with GPU offloading', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      final gpuRepo = LlamaCppChatRepository(
        contextSize: 512,
        nGpuLayers: 99, // Try to offload all layers
      );

      try {
        print('Loading with GPU offloading (nGpuLayers=99)...');
        await gpuRepo.loadModel(
          modelPath,
          options: const ModelLoadOptions(nGpuLayers: 99),
        );

        expect(gpuRepo.isModelLoaded, isTrue);
        print('✅ Model loaded with GPU offloading');
      } finally {
        gpuRepo.dispose();
      }
    });

    test('loads model with memory mapping disabled', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      print('Loading without memory mapping...');
      await repo.loadModel(
        modelPath,
        options: const ModelLoadOptions(useMemoryMap: false),
      );

      expect(repo.isModelLoaded, isTrue);
      print('✅ Model loaded without mmap');
    });

    test('throws on invalid model path', () async {
      expect(
        () => repo.loadModel('/nonexistent/path/model.gguf'),
        throwsException,
      );
    });

    test('throws on invalid file format', () async {
      // Create a temporary invalid file
      final tempFile = File('/tmp/invalid_model_test.gguf');
      tempFile.writeAsBytesSync([0, 1, 2, 3]); // Not a valid GGUF

      try {
        expect(() => repo.loadModel(tempFile.path), throwsException);
      } finally {
        tempFile.deleteSync();
      }
    });

    test('can unload and reload model', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      // Load
      await repo.loadModel(modelPath);
      expect(repo.isModelLoaded, isTrue);

      // Unload
      repo.unloadModel();
      expect(repo.isModelLoaded, isFalse);
      expect(repo.model, isNull);

      // Reload
      await repo.loadModel(modelPath);
      expect(repo.isModelLoaded, isTrue);
    });

    test('replaces model when loading new one', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      // Load first time
      await repo.loadModel(modelPath);
      final firstVocabSize = repo.model!.vocabSize;

      // Load again (should replace)
      await repo.loadModel(modelPath);
      expect(repo.model!.vocabSize, equals(firstVocabSize));
    });

    test('model reports correct special tokens', () async {
      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath);

      // Special tokens should be valid indices
      expect(repo.model!.bosToken, greaterThanOrEqualTo(0));
      expect(repo.model!.eosToken, greaterThanOrEqualTo(0));
      expect(repo.model!.bosToken, lessThan(repo.model!.vocabSize));
      expect(repo.model!.eosToken, lessThan(repo.model!.vocabSize));

      // EOS should be recognized as EOG
      expect(repo.model!.isEogToken(repo.model!.eosToken), isTrue);
    });
  });

  group('Model Metadata', () {
    late LlamaCppChatRepository repo;

    setUp(() async {
      repo = LlamaCppChatRepository(
        contextSize: 512,
        nGpuLayers: config.gpuLayers,
      );

      final modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath != null) {
        await repo.loadModel(modelPath);
      }
    });

    tearDown(() {
      repo.dispose();
    });

    test('exposes vocabulary size', () {
      if (!repo.isModelLoaded) {
        markTestSkipped('No model available');
        return;
      }

      // Most models have vocab size > 30000
      expect(repo.model!.vocabSize, greaterThan(1000));
    });

    test('exposes training context size', () {
      if (!repo.isModelLoaded) {
        markTestSkipped('No model available');
        return;
      }

      // Most models have context >= 2048
      expect(repo.model!.contextSizeTrain, greaterThanOrEqualTo(2048));
    });

    test('exposes embedding dimension', () {
      if (!repo.isModelLoaded) {
        markTestSkipped('No model available');
        return;
      }

      // Embedding dimension should be reasonable
      expect(repo.model!.embeddingSize, greaterThan(256));
      expect(repo.model!.embeddingSize, lessThan(100000));
    });
  });
}
