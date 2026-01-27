/// Integration tests for Embeddings
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Embeddings', () {
    late OllamaChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    group('Embedding Tests', () {
      test(
        'single text embedding',
        () async {
          final embeddings = await repo
              .embed(model: embeddingModel, messages: ['Hello world'])
              .timeout(const Duration(seconds: 60));

          expect(embeddings, isNotEmpty);
          expect(embeddings.length, equals(1));
          expect(embeddings[0].embedding, isNotEmpty);
          expect(embeddings[0].embedding.length, greaterThan(0));
          expect(embeddings[0].model, equals(embeddingModel));
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'batch embeddings',
        () async {
          final texts = ['Hello world', 'Goodbye world', 'Test embedding'];
          final embeddings = await repo
              .embed(model: embeddingModel, messages: texts)
              .timeout(const Duration(seconds: 60));

          expect(embeddings.length, equals(texts.length));
          for (final embedding in embeddings) {
            expect(embedding.embedding, isNotEmpty);
            expect(embedding.model, equals(embeddingModel));
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'empty string embedding',
        () async {
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [''])
              .timeout(const Duration(seconds: 60));

          expect(embeddings, isNotEmpty);
          expect(embeddings[0].embedding, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'very long text embedding',
        () async {
          final longText = 'This is a very long text. ' * 100;
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [longText])
              .timeout(const Duration(seconds: 60));

          expect(embeddings, isNotEmpty);
          expect(embeddings[0].embedding, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'special characters in embedding',
        () async {
          const specialText = 'Hello! 🌍 你好 مرحبا\n\t{"key": "value"}';
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [specialText])
              .timeout(const Duration(seconds: 60));

          expect(embeddings, isNotEmpty);
          expect(embeddings[0].embedding, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'embedding dimensions consistency',
        () async {
          final texts = ['Text 1', 'Text 2', 'Text 3'];
          final embeddings = await repo
              .embed(model: embeddingModel, messages: texts)
              .timeout(const Duration(seconds: 60));

          expect(embeddings.length, equals(texts.length));
          final dimension = embeddings[0].embedding.length;
          expect(dimension, greaterThan(0));

          // All embeddings should have the same dimension
          for (final embedding in embeddings) {
            expect(embedding.embedding.length, equals(dimension));
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'embedding similarity - similar texts',
        () async {
          const text1 = 'The cat sat on the mat';
          const text2 = 'A cat was sitting on a mat';
          const text3 = 'The weather is sunny today';

          final embeddings = await repo
              .embed(model: embeddingModel, messages: [text1, text2, text3])
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
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'embedding consistency - same text',
        () async {
          const text = 'Consistency test text';
          final embeddings1 = await repo
              .embed(model: embeddingModel, messages: [text])
              .timeout(const Duration(seconds: 60));
          final embeddings2 = await repo
              .embed(model: embeddingModel, messages: [text])
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
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'large batch embeddings',
        () async {
          final texts = List.generate(
            50,
            (i) => 'Text number $i for batch embedding test',
          );
          final embeddings = await repo
              .embed(model: embeddingModel, messages: texts)
              .timeout(const Duration(minutes: 2));

          expect(embeddings.length, equals(texts.length));
          for (final embedding in embeddings) {
            expect(embedding.embedding, isNotEmpty);
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'embedding normalization',
        () async {
          const text = 'Test normalization';
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [text])
              .timeout(const Duration(seconds: 60));

          final embedding = embeddings[0].embedding;
          // Check that embedding values are reasonable (not NaN, not infinite)
          for (final value in embedding) {
            expect(
              value.isFinite,
              isTrue,
              reason: 'Embedding values should be finite',
            );
            expect(
              value.isNaN,
              isFalse,
              reason: 'Embedding values should not be NaN',
            );
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'embedding dimension validation',
        () async {
          const text = 'Test dimension';
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [text])
              .timeout(const Duration(seconds: 60));

          final dimension = embeddings[0].embedding.length;
          // nomic-embed-text should have a specific dimension
          expect(
            dimension,
            greaterThan(0),
            reason: 'Embedding dimension should be positive',
          );
          expect(
            dimension,
            lessThan(10000),
            reason: 'Embedding dimension should be reasonable',
          );

          // All embeddings from the same model should have the same dimension
          final texts = ['Text 1', 'Text 2', 'Text 3'];
          final batchEmbeddings = await repo
              .embed(model: embeddingModel, messages: texts)
              .timeout(const Duration(seconds: 60));

          for (final embedding in batchEmbeddings) {
            expect(
              embedding.embedding.length,
              equals(dimension),
              reason: 'All embeddings should have consistent dimensions',
            );
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );
    });
  });
}
