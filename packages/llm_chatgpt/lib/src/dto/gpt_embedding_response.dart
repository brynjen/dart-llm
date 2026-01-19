import 'package:llm_core/llm_core.dart';

/// Response from OpenAI embeddings endpoint.
class ChatGPTEmbeddingsResponse {
  ChatGPTEmbeddingsResponse({
    required this.model,
    required this.data,
    required this.usage,
  });

  final String model;
  final String object = 'list';
  final ChatGPTEmbeddingsUsage usage;
  final List<ChatGPTEmbedding> data;

  factory ChatGPTEmbeddingsResponse.fromJson(Map<String, dynamic> json) =>
      ChatGPTEmbeddingsResponse(
        model: json['model'],
        usage: ChatGPTEmbeddingsUsage.fromJson(json['usage']),
        data: (json['data'] as List<dynamic>)
            .map((embeddingJson) => ChatGPTEmbedding.fromJson(embeddingJson))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'model': model,
        'object': object,
        'usage': usage.toJson(),
        'data':
            data.map((dataJson) => dataJson.toJson()).toList(growable: false),
      };
}

/// A single embedding in the response.
class ChatGPTEmbedding {
  ChatGPTEmbedding({required this.index, required this.embedding});

  final String object = 'embedding';
  final int index;
  final List<double> embedding;

  factory ChatGPTEmbedding.fromJson(Map<String, dynamic> json) =>
      ChatGPTEmbedding(
        index: json['index'],
        embedding: (json['embedding'] as List<dynamic>)
            .map((e) => e as double)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'object': object,
        'embedding': embedding,
      };
}

/// Token usage for embedding requests.
class ChatGPTEmbeddingsUsage {
  ChatGPTEmbeddingsUsage({
    required this.promptTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int totalTokens;

  factory ChatGPTEmbeddingsUsage.fromJson(Map<String, dynamic> json) =>
      ChatGPTEmbeddingsUsage(
        promptTokens: json['prompt_tokens'],
        totalTokens: json['total_tokens'],
      );

  Map<String, dynamic> toJson() => {
        'prompt_tokens': promptTokens,
        'total_tokens': totalTokens,
      };
}

/// Extension to convert ChatGPT embeddings response to LLM embeddings.
extension ChatGPTLLMEmbedding on ChatGPTEmbeddingsResponse {
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

