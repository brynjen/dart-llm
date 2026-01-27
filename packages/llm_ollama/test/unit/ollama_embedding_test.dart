import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaEmbeddingResponse', () {
    test('fromJson with all fields', () {
      final json = {
        'model': 'nomic-embed-text',
        'total_duration': 1000,
        'load_duration': 500,
        'prompt_eval_count': 5,
        'embeddings': [
          [0.1, 0.2, 0.3],
          [0.4, 0.5, 0.6],
        ],
      };

      final response = OllamaEmbeddingResponse.fromJson(json);

      expect(response.model, 'nomic-embed-text');
      expect(response.totalDuration, 1000);
      expect(response.loadDuration, 500);
      expect(response.promptEvalCount, 5);
      expect(response.embeddings.length, 2);
      expect(response.embeddings[0], [0.1, 0.2, 0.3]);
      expect(response.embeddings[1], [0.4, 0.5, 0.6]);
    });

    test('toJson roundtrip', () {
      final original = OllamaEmbeddingResponse(
        model: 'nomic-embed-text',
        totalDuration: 1000,
        loadDuration: 500,
        promptEvalCount: 5,
        embeddings: [
          [0.1, 0.2, 0.3],
          [0.4, 0.5, 0.6],
        ],
      );

      final json = original.toJson();
      final reconstructed = OllamaEmbeddingResponse.fromJson(json);

      expect(reconstructed.model, original.model);
      expect(reconstructed.totalDuration, original.totalDuration);
      expect(reconstructed.loadDuration, original.loadDuration);
      expect(reconstructed.promptEvalCount, original.promptEvalCount);
      expect(reconstructed.embeddings, original.embeddings);
    });

    test('toLLMEmbedding extension', () {
      final response = OllamaEmbeddingResponse(
        model: 'nomic-embed-text',
        totalDuration: 1000,
        loadDuration: 500,
        promptEvalCount: 5,
        embeddings: [
          [0.1, 0.2, 0.3],
          [0.4, 0.5, 0.6],
        ],
      );

      final llmEmbeddings = response.toLLMEmbedding;

      expect(llmEmbeddings.length, 2);
      expect(llmEmbeddings[0].model, 'nomic-embed-text');
      expect(llmEmbeddings[0].embedding, [0.1, 0.2, 0.3]);
      expect(llmEmbeddings[0].promptEvalCount, 5);
      expect(llmEmbeddings[1].embedding, [0.4, 0.5, 0.6]);
    });

    test('fromJson with empty embeddings', () {
      final json = {
        'model': 'nomic-embed-text',
        'total_duration': 1000,
        'load_duration': 500,
        'prompt_eval_count': 0,
        'embeddings': <List<double>>[],
      };

      final response = OllamaEmbeddingResponse.fromJson(json);

      expect(response.embeddings, isEmpty);
    });
  });
}
