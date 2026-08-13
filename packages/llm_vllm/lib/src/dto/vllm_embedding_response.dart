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

  /// Throws [FormatException] when `data` is missing or not a list — an
  /// embeddings response without embeddings is unrecoverable, and a
  /// [FormatException] lets the caller translate it into a domain exception
  /// instead of leaking a raw [TypeError].
  factory VLLMEmbeddingsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! List) {
      throw const FormatException('embeddings response has no "data" list');
    }
    return VLLMEmbeddingsResponse(
      model: json['model'] as String? ?? '',
      usage: VLLMEmbeddingsUsage.fromJson(
        json['usage'] as Map<String, dynamic>? ?? const {},
      ),
      data: data
          .map(
            (embeddingJson) => switch (embeddingJson) {
              Map<String, dynamic>() => VLLMEmbedding.fromJson(embeddingJson),
              _ => throw const FormatException(
                'embeddings response "data" entry is not an object',
              ),
            },
          )
          .toList(growable: false),
    );
  }

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

  /// Throws [FormatException] when `embedding` is missing, not a list, or
  /// holds non-numeric entries — see [VLLMEmbeddingsResponse.fromJson].
  factory VLLMEmbedding.fromJson(Map<String, dynamic> json) {
    final embedding = json['embedding'];
    if (embedding is! List) {
      throw const FormatException(
        'embeddings response entry has no "embedding" list',
      );
    }
    return VLLMEmbedding(
      index: json['index'] as int? ?? 0,
      embedding: embedding
          .map(
            (e) => switch (e) {
              num() => e.toDouble(),
              _ => throw const FormatException(
                'embeddings response vector holds a non-numeric value',
              ),
            },
          )
          .toList(growable: false),
    );
  }

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
