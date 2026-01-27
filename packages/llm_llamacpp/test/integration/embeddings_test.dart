// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:math';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// Calculates cosine similarity between two vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have the same length');
  }
  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0.0 || normB == 0.0) return 0.0;
  return dotProduct / (sqrt(normA) * sqrt(normB));
}

/// Tests for embedding generation functionality.
void main() {
  final config = TestConfig.instance;

  group('Embeddings', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
      // ignore: avoid_print
      if (modelPath == null) {
        // ignore: avoid_print
        print('⚠️  No model available for embedding tests');
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

    test(
      'generates single text embedding',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final embeddings = await repo
            .embed(model: 'test', messages: ['Hello world'])
            .timeout(const Duration(seconds: 60));

        expect(embeddings, isNotEmpty);
        expect(embeddings.length, equals(1));
        expect(embeddings[0].embedding, isNotEmpty);
        expect(embeddings[0].embedding.length, greaterThan(0));
        expect(embeddings[0].model, equals('test'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('generates batch embeddings', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final texts = ['Hello world', 'Goodbye world', 'Test embedding'];
      final embeddings = await repo
          .embed(model: 'test', messages: texts)
          .timeout(const Duration(seconds: 60));

      expect(embeddings.length, equals(texts.length));
      for (final embedding in embeddings) {
        expect(embedding.embedding, isNotEmpty);
        expect(embedding.model, equals('test'));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'embedding dimensions consistency',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final texts = ['Text 1', 'Text 2', 'Text 3'];
        final embeddings = await repo
            .embed(model: 'test', messages: texts)
            .timeout(const Duration(seconds: 60));

        expect(embeddings.length, equals(texts.length));
        final dimension = embeddings[0].embedding.length;
        expect(dimension, greaterThan(0));

        // All embeddings should have the same dimension
        for (final embedding in embeddings) {
          expect(embedding.embedding.length, equals(dimension));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'embedding similarity - similar texts',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        const text1 = 'The cat sat on the mat';
        const text2 = 'A cat was sitting on a mat';
        const text3 = 'The weather is sunny today';

        final embeddings = await repo
            .embed(model: 'test', messages: [text1, text2, text3])
            .timeout(const Duration(seconds: 60));

        expect(embeddings.length, equals(3));

        final similarity12 = cosineSimilarity(
          embeddings[0].embedding,
          embeddings[1].embedding,
        );
        final similarity13 = cosineSimilarity(
          embeddings[0].embedding,
          embeddings[2].embedding,
        );

        // Similar texts should have higher similarity
        expect(
          similarity12,
          greaterThan(similarity13),
          reason: 'Similar texts should have higher cosine similarity',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'embedding consistency - same text',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        const text = 'Consistency test text';
        final embeddings1 = await repo
            .embed(model: 'test', messages: [text])
            .timeout(const Duration(seconds: 60));
        final embeddings2 = await repo
            .embed(model: 'test', messages: [text])
            .timeout(const Duration(seconds: 60));

        expect(
          embeddings1[0].embedding.length,
          equals(embeddings2[0].embedding.length),
        );
        // Embeddings should be very similar (may not be identical due to floating point)
        final similarity = cosineSimilarity(
          embeddings1[0].embedding,
          embeddings2[0].embedding,
        );
        expect(
          similarity,
          greaterThan(0.99),
          reason: 'Same text should produce very similar embeddings',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'handles empty string embedding',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final embeddings = await repo
            .embed(model: 'test', messages: [''])
            .timeout(const Duration(seconds: 60));

        expect(embeddings, isNotEmpty);
        expect(embeddings[0].embedding, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'handles very long text embedding',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final longText = 'This is a very long text. ' * 100;
        final embeddings = await repo
            .embed(model: 'test', messages: [longText])
            .timeout(const Duration(seconds: 60));

        expect(embeddings, isNotEmpty);
        expect(embeddings[0].embedding, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'handles special characters in embedding',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        final specialText = 'Hello! 🌍 你好 مرحبا\n\t{"key": "value"}';
        final embeddings = await repo
            .embed(model: 'test', messages: [specialText])
            .timeout(const Duration(seconds: 60));

        expect(embeddings, isNotEmpty);
        expect(embeddings[0].embedding, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('throws when no model loaded', () async {
      // Don't load a model
      expect(() async {
        await repo.embed(model: 'test', messages: ['Hello']);
      }, throwsA(isA<ModelLoadException>()));
    });

    test('throws on empty messages', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      expect(() async {
        await repo.embed(model: 'test', messages: []);
      }, throwsA(isA<LLMApiException>()));
    });
  });
}
