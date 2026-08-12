import 'package:llm_core/llm_core.dart';

/// Response from vLLM embeddings endpoint.
class VLLMEmbeddingsResponse {
  VLLMEmbeddingsResponse({
    required this.model,
    required this.data,
    required this.usage,
  });

  final String model;
  final String object = 'list';
  final VLLMEmbeddingsUsage usage;
  final List<VLLMEmbedding> data;

  factory VLLMEmbeddingsResponse.fromJson(Map<String, dynamic> json) =>
      VLLMEmbeddingsResponse(
        model: json['model'],
        usage: VLLMEmbeddingsUsage.fromJson(
          json['usage'] as Map<String, dynamic>? ?? const {},
        ),
        data: (json['data'] as List<dynamic>)
            .map((embeddingJson) => VLLMEmbedding.fromJson(embeddingJson))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'model': model,
    'object': object,
    'usage': usage.toJson(),
    'data': data.map((dataJson) => dataJson.toJson()).toList(growable: false),
  };
}

/// A single embedding in the response.
class VLLMEmbedding {
  VLLMEmbedding({required this.index, required this.embedding});

  final String object = 'embedding';
  final int index;
  final List<double> embedding;

  factory VLLMEmbedding.fromJson(Map<String, dynamic> json) => VLLMEmbedding(
    index: json['index'],
    embedding: (json['embedding'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'object': object,
    'embedding': embedding,
  };
}

/// Token usage for embedding requests.
class VLLMEmbeddingsUsage {
  VLLMEmbeddingsUsage({required this.promptTokens, required this.totalTokens});

  final int promptTokens;
  final int totalTokens;

  factory VLLMEmbeddingsUsage.fromJson(Map<String, dynamic> json) =>
      VLLMEmbeddingsUsage(
        promptTokens: json['prompt_tokens'] as int? ?? 0,
        totalTokens:
            json['total_tokens'] as int? ?? json['prompt_tokens'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'prompt_tokens': promptTokens,
    'total_tokens': totalTokens,
  };
}

/// Extension to convert vLLM embeddings response to LLM embeddings.
extension VLLMLLMEmbedding on VLLMEmbeddingsResponse {
  List<LLMEmbedding> get toLLMEmbedding => data
      .map(
        (embedding) => LLMEmbedding(
          model: model,
          embedding: embedding.embedding,
          promptEvalCount: usage.promptTokens,
        ),
      )
      .toList(growable: false);
}
