import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMEmbedding', () {
    test('fromJson with all fields', () {
      final json = {
        'model': 'text-embedding-3-small',
        'embeddings': [0.1, 0.2, 0.3, 0.4, 0.5],
        'prompt_eval_count': 5,
      };

      final embedding = LLMEmbedding.fromJson(json);

      expect(embedding.model, 'text-embedding-3-small');
      expect(embedding.embedding, [0.1, 0.2, 0.3, 0.4, 0.5]);
      expect(embedding.promptEvalCount, 5);
    });

    test('fromJson with empty embedding vector', () {
      final json = {
        'model': 'text-embedding-3-small',
        'embeddings': <double>[],
        'prompt_eval_count': 0,
      };

      final embedding = LLMEmbedding.fromJson(json);

      expect(embedding.embedding, isEmpty);
      expect(embedding.promptEvalCount, 0);
    });

    test('fromJson with large embedding vector', () {
      final largeVector = List.generate(1536, (i) => i * 0.001);
      final json = {
        'model': 'text-embedding-3-small',
        'embeddings': largeVector,
        'prompt_eval_count': 10,
      };

      final embedding = LLMEmbedding.fromJson(json);

      expect(embedding.embedding.length, 1536);
      expect(embedding.embedding.first, 0.0);
      expect(embedding.embedding.last, closeTo(1.535, 0.0001));
    });

    test('construction with all fields', () {
      final embedding = LLMEmbedding(
        model: 'text-embedding-3-small',
        embedding: [0.1, 0.2, 0.3],
        promptEvalCount: 5,
      );

      expect(embedding.model, 'text-embedding-3-small');
      expect(embedding.embedding, [0.1, 0.2, 0.3]);
      expect(embedding.promptEvalCount, 5);
    });
  });
}
