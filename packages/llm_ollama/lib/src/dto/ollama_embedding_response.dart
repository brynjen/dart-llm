import 'package:llm_core/llm_core.dart';

/// Response from Ollama's embedding endpoint.
class OllamaEmbeddingResponse {
  OllamaEmbeddingResponse({
    required this.model,
    required this.totalDuration,
    required this.loadDuration,
    required this.promptEvalCount,
    required this.embeddings,
  });

  final String model;
  final int totalDuration;
  final int loadDuration;
  final int promptEvalCount;
  final List<List<double>> embeddings;

  factory OllamaEmbeddingResponse.fromJson(Map<String, dynamic> json) =>
      OllamaEmbeddingResponse(
        model: json['model'],
        totalDuration: json['total_duration'],
        loadDuration: json['load_duration'],
        embeddings: (json['embeddings'] as List<dynamic>)
            .map((embedding) => (embedding as List<dynamic>).cast<double>())
            .toList(growable: false),
        promptEvalCount: json['prompt_eval_count'],
      );

  Map<String, dynamic> toJson() => {
        'model': model,
        'total_duration': totalDuration,
        'load_duration': loadDuration,
        'prompt_eval_count': promptEvalCount,
        'embeddings': embeddings,
      };
}

/// Extension to convert Ollama embedding response to LLM embeddings.
extension OllamaEmbeddingExt on OllamaEmbeddingResponse {
  List<LLMEmbedding> get toLLMEmbedding => embeddings
      .map(
        (embedding) => LLMEmbedding(
          model: model,
          embedding: embedding,
          promptEvalCount: promptEvalCount,
        ),
      )
      .toList(growable: false);
}

