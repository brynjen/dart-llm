import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiUsage', () {
    test('fromJson maps Interactions field names', () {
      final usage = GeminiUsage.fromJson({
        'total_tokens': 130,
        'total_input_tokens': 80,
        'total_output_tokens': 40,
        'total_cached_tokens': 5,
        'total_thought_tokens': 10,
        'total_tool_use_tokens': 2,
      });

      expect(usage.totalTokens, 130);
      expect(usage.inputTokens, 80);
      expect(usage.outputTokens, 40);
      expect(usage.cachedTokens, 5);
      expect(usage.thoughtTokens, 10);
      expect(usage.toolUseTokens, 2);
    });

    test('fromJson with missing fields defaults to 0', () {
      final usage = GeminiUsage.fromJson({});

      expect(usage.totalTokens, 0);
      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
      expect(usage.cachedTokens, 0);
      expect(usage.thoughtTokens, 0);
      expect(usage.toolUseTokens, 0);
    });

    test('fromJson ignores legacy generateContent field names', () {
      final usage = GeminiUsage.fromJson({
        'promptTokenCount': 10,
        'candidatesTokenCount': 20,
      });

      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
    });

    test('fromJson handles numeric types', () {
      final usage = GeminiUsage.fromJson({
        'total_input_tokens': 100.0,
        'total_output_tokens': 200.0,
      });

      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 200);
    });

    test('toLLMUsage maps input/output onto prompt/completion tokens', () {
      final usage = const GeminiUsage(
        totalTokens: 130,
        inputTokens: 80,
        outputTokens: 40,
      ).toLLMUsage();

      expect(usage.promptTokens, 80);
      expect(usage.completionTokens, 40);
      expect(usage.totalTokens, 130);
    });

    test('toLLMUsage falls back to the sum when total is absent', () {
      final usage = const GeminiUsage(
        inputTokens: 8,
        outputTokens: 2,
      ).toLLMUsage();

      expect(usage.totalTokens, 10);
    });

    test('toProviderMetadata surfaces counters without a core slot', () {
      final metadata = const GeminiUsage(
        totalTokens: 130,
        inputTokens: 80,
        outputTokens: 40,
        cachedTokens: 5,
        thoughtTokens: 10,
        toolUseTokens: 2,
      ).toProviderMetadata();

      expect(metadata, {
        'total_tokens': 130,
        'total_cached_tokens': 5,
        'total_thought_tokens': 10,
        'total_tool_use_tokens': 2,
      });
    });
  });

  group('GeminiChunk', () {
    test('creates with all fields', () {
      final now = DateTime.now();
      final chunk = GeminiChunk(
        model: 'gemini-3.5-flash-lite',
        done: true,
        createdAt: now,
        promptEvalCount: 10,
        evalCount: 20,
      );

      expect(chunk.model, 'gemini-3.5-flash-lite');
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
      final chunk = GeminiChunk(model: 'gemini-3.5-flash-lite');
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

      final embedding = response.toLLMEmbedding('gemini-embedding-001');

      expect(embedding.model, 'gemini-embedding-001');
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

      final embeddings = response.toLLMEmbeddings('gemini-embedding-001');

      expect(embeddings.length, 2);
      expect(embeddings[0].model, 'gemini-embedding-001');
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
