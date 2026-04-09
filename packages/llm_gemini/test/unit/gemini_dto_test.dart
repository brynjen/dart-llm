import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiUsage', () {
    test('fromJson with all fields', () {
      final usage = GeminiUsage.fromJson({
        'promptTokenCount': 10,
        'candidatesTokenCount': 20,
      });

      expect(usage.promptTokenCount, 10);
      expect(usage.candidatesTokenCount, 20);
    });

    test('fromJson with missing fields defaults to 0', () {
      final usage = GeminiUsage.fromJson({});

      expect(usage.promptTokenCount, 0);
      expect(usage.candidatesTokenCount, 0);
    });

    test('fromJson with null values defaults to 0', () {
      final usage = GeminiUsage.fromJson({
        'promptTokenCount': null,
        'candidatesTokenCount': null,
      });

      expect(usage.promptTokenCount, 0);
      expect(usage.candidatesTokenCount, 0);
    });

    test('fromJson handles numeric types', () {
      final usage = GeminiUsage.fromJson({
        'promptTokenCount': 100.0,
        'candidatesTokenCount': 200.0,
      });

      expect(usage.promptTokenCount, 100);
      expect(usage.candidatesTokenCount, 200);
    });
  });

  group('GeminiChunk', () {
    test('creates with all fields', () {
      final now = DateTime.now();
      final chunk = GeminiChunk(
        model: 'gemini-2.0-flash',
        done: true,
        createdAt: now,
        promptEvalCount: 10,
        evalCount: 20,
      );

      expect(chunk.model, 'gemini-2.0-flash');
      expect(chunk.done, isTrue);
      expect(chunk.createdAt, now);
      expect(chunk.promptEvalCount, 10);
      expect(chunk.evalCount, 20);
    });

    test('creates with default values', () {
      final chunk = GeminiChunk();

      expect(chunk.model, isNull);
      expect(chunk.done, isNull);
      expect(chunk.message, isNull);
      expect(chunk.promptEvalCount, isNull);
      expect(chunk.evalCount, isNull);
    });

    test('is an LLMChunk', () {
      final chunk = GeminiChunk(model: 'gemini-2.0-flash');
      expect(chunk, isA<LLMChunk>());
    });
  });

  group('GeminiEmbeddingResponse', () {
    test('fromJson with values', () {
      final response = GeminiEmbeddingResponse.fromJson({
        'embedding': {
          'values': [0.1, 0.2, 0.3],
        },
      });

      expect(response.values, [0.1, 0.2, 0.3]);
    });

    test('fromJson with missing embedding defaults to empty', () {
      final response = GeminiEmbeddingResponse.fromJson({});

      expect(response.values, isEmpty);
    });

    test('fromJson with missing values defaults to empty', () {
      final response = GeminiEmbeddingResponse.fromJson({
        'embedding': <String, dynamic>{},
      });

      expect(response.values, isEmpty);
    });

    test('toLLMEmbedding converts correctly', () {
      final response = GeminiEmbeddingResponse.fromJson({
        'embedding': {
          'values': [0.1, 0.2, 0.3],
        },
      });

      final embedding = response.toLLMEmbedding('text-embedding-004');

      expect(embedding.model, 'text-embedding-004');
      expect(embedding.embedding, [0.1, 0.2, 0.3]);
      expect(embedding.promptEvalCount, 0);
    });
  });

  group('GeminiBatchEmbeddingResponse', () {
    test('fromJson with multiple embeddings', () {
      final response = GeminiBatchEmbeddingResponse.fromJson({
        'embeddings': [
          {
            'values': [0.1, 0.2],
          },
          {
            'values': [0.3, 0.4],
          },
        ],
      });

      expect(response.embeddings.length, 2);
      expect(response.embeddings[0], [0.1, 0.2]);
      expect(response.embeddings[1], [0.3, 0.4]);
    });

    test('fromJson with missing embeddings defaults to empty', () {
      final response = GeminiBatchEmbeddingResponse.fromJson({});

      expect(response.embeddings, isEmpty);
    });

    test('toLLMEmbeddings converts correctly', () {
      final response = GeminiBatchEmbeddingResponse.fromJson({
        'embeddings': [
          {
            'values': [0.1, 0.2],
          },
          {
            'values': [0.3, 0.4],
          },
        ],
      });

      final embeddings = response.toLLMEmbeddings('text-embedding-004');

      expect(embeddings.length, 2);
      expect(embeddings[0].model, 'text-embedding-004');
      expect(embeddings[0].embedding, [0.1, 0.2]);
      expect(embeddings[1].embedding, [0.3, 0.4]);
    });

    test('fromJson handles integer values in embedding', () {
      final response = GeminiBatchEmbeddingResponse.fromJson({
        'embeddings': [
          {
            'values': [1, 2, 3],
          },
        ],
      });

      expect(response.embeddings[0], [1.0, 2.0, 3.0]);
    });
  });
}
