import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('VLLMEmbeddingsResponse', () {
    test('fromJson and toJson roundtrip', () {
      final json = {
        'model': 'embedding-model',
        'object': 'list',
        'usage': {'prompt_tokens': 5, 'total_tokens': 5},
        'data': [
          {
            'object': 'embedding',
            'index': 0,
            'embedding': [0.1, 0.2, 0.3],
          },
          {
            'object': 'embedding',
            'index': 1,
            'embedding': [1, 2, 3],
          },
        ],
      };

      final response = VLLMEmbeddingsResponse.fromJson(json);
      final reconstructed = response.toJson();

      expect(response.model, 'embedding-model');
      expect(response.object, 'list');
      expect(response.data.length, 2);
      expect(response.usage.promptTokens, 5);
      expect(response.usage.totalTokens, 5);
      expect(response.data[1].embedding, [1.0, 2.0, 3.0]);
      expect(reconstructed['model'], 'embedding-model');
      expect(reconstructed['object'], 'list');
    });

    test('toLLMEmbedding converts correctly', () {
      final response = VLLMEmbeddingsResponse(
        model: 'embedding-model',
        usage: VLLMEmbeddingsUsage(promptTokens: 5, totalTokens: 5),
        data: [
          VLLMEmbedding(index: 0, embedding: [0.1, 0.2, 0.3]),
          VLLMEmbedding(index: 1, embedding: [0.4, 0.5, 0.6]),
        ],
      );

      final llmEmbeddings = response.toLLMEmbedding;

      expect(llmEmbeddings.length, 2);
      expect(llmEmbeddings[0].model, 'embedding-model');
      expect(llmEmbeddings[0].embedding, [0.1, 0.2, 0.3]);
      expect(llmEmbeddings[0].promptEvalCount, 5);
      expect(llmEmbeddings[1].embedding, [0.4, 0.5, 0.6]);
    });
  });
}
