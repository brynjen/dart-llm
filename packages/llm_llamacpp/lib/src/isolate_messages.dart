import 'dart:isolate';

import 'package:llm_core/llm_core.dart' show LLMEmbedding;
import 'package:llm_llamacpp/src/generation_options.dart';

/// A simple message representation that can be passed between isolates.
///
/// This is a lightweight alternative to LLMMessage that avoids any
/// complex types that might not serialize well across isolate boundaries.
class IsolateMessage {
  const IsolateMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// Request message for inference operations in an isolate.
class InferenceRequest {
  InferenceRequest({
    required this.sendPort,
    required this.modelPath,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    required this.options,
    this.threads,
    this.loraPath,
    this.loraScale = 1.0,
    this.messages,
  });

  final SendPort sendPort;
  final String modelPath;

  /// Pre-formatted prompt string (legacy - deprecated).
  /// When [messages] is provided, this is ignored and the native
  /// llama_chat_apply_template() is used instead.
  final String prompt;

  /// Raw chat messages for native template formatting.
  /// When provided, uses the GGUF's built-in chat template via
  /// llama_chat_apply_template() instead of manual Dart templates.
  final List<IsolateMessage>? messages;

  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int nGpuLayers;
  final GenerationOptions options;

  // LoRA configuration
  final String? loraPath;
  final double loraScale;
}

/// Token message sent during inference streaming.
class InferenceToken {
  InferenceToken(this.token);
  final String token;
}

/// Completion message indicating inference is finished.
class InferenceComplete {
  InferenceComplete({
    required this.promptTokens,
    required this.generatedTokens,
  });
  final int promptTokens;
  final int generatedTokens;
}

/// Error message sent when inference fails.
class InferenceError {
  InferenceError(this.error);
  final String error;
}

/// Request message for embedding operations in an isolate.
class EmbeddingRequest {
  EmbeddingRequest({
    required this.sendPort,
    required this.modelPath,
    required this.messages,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    this.threads,
  });

  final SendPort sendPort;
  final String modelPath;
  final List<String> messages;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int nGpuLayers;
}

/// Result message containing an embedding.
class EmbeddingResult {
  EmbeddingResult(this.embedding);
  final LLMEmbedding embedding;
}

/// Error message sent when embedding extraction fails.
class EmbeddingError {
  EmbeddingError(this.error);
  final String error;
}

/// Completion message indicating embedding extraction is finished.
class EmbeddingComplete {
  EmbeddingComplete();
}
