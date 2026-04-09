/// Integration tests for Embeddings
///
/// Part of the comprehensive Gemini integration test suite.
///
/// Requires API key to be set via GEMINI_API_KEY environment variable.
library;

import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Gemini Integration Tests - Embeddings', () {
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

    group('Embedding Tests', () {
      test(
        'single text embedding',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
        'batchEmbed returns same length and dimensions as embed',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final texts = ['First', 'Second', 'Third'];
          final embedResults = await repo
              .embed(model: embeddingModel, messages: texts)
              .timeout(const Duration(seconds: 60));
          final batchEmbedResults = await repo
              .batchEmbed(model: embeddingModel, messages: texts)
              .timeout(const Duration(seconds: 60));

          expect(batchEmbedResults.length, equals(texts.length));
          expect(batchEmbedResults.length, equals(embedResults.length));
          final dimension = embedResults[0].embedding.length;
          for (var i = 0; i < batchEmbedResults.length; i++) {
            expect(batchEmbedResults[i].embedding, isNotEmpty);
            expect(batchEmbedResults[i].embedding.length, equals(dimension));
            expect(batchEmbedResults[i].model, equals(embeddingModel));
          }
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'very long text embedding',
        () async {
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          final texts = List.generate(
            20,
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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

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
          if (!hasApiKey()) {
            markTestSkipped('API key not available');
            return;
          }

          const text = 'Test dimension';
          final embeddings = await repo
              .embed(model: embeddingModel, messages: [text])
              .timeout(const Duration(seconds: 60));

          final dimension = embeddings[0].embedding.length;
          // text-embedding-004 should have 768 dimensions
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
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 1)),
      );
    });
  });
}
