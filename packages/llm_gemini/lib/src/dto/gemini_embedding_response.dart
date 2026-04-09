import 'package:llm_core/llm_core.dart';

/// Response from the Gemini embedContent endpoint.
class GeminiEmbeddingResponse {
  const GeminiEmbeddingResponse({required this.values});

  factory GeminiEmbeddingResponse.fromJson(Map<String, dynamic> json) {
    final embedding = json['embedding'] as Map<String, dynamic>? ?? {};
    final values =
        (embedding['values'] as List<dynamic>?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [];
    return GeminiEmbeddingResponse(values: values);
  }

  final List<double> values;

  LLMEmbedding toLLMEmbedding(String model) {
    return LLMEmbedding(model: model, embedding: values, promptEvalCount: 0);
  }
}

/// Response from the Gemini batchEmbedContents endpoint.
class GeminiBatchEmbeddingResponse {
  const GeminiBatchEmbeddingResponse({required this.embeddings});

  factory GeminiBatchEmbeddingResponse.fromJson(Map<String, dynamic> json) {
    final list = json['embeddings'] as List<dynamic>? ?? [];
    final embeddings = list.map((e) {
      final values =
          (e['values'] as List<dynamic>?)
              ?.map((v) => (v as num).toDouble())
              .toList() ??
          [];
      return values;
    }).toList();
    return GeminiBatchEmbeddingResponse(embeddings: embeddings);
  }

  final List<List<double>> embeddings;

  List<LLMEmbedding> toLLMEmbeddings(String model) {
    return embeddings
        .map(
          (v) => LLMEmbedding(model: model, embedding: v, promptEvalCount: 0),
        )
        .toList();
  }
}
