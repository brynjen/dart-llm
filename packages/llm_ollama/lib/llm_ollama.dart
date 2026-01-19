/// Ollama backend implementation for LLM interactions.
///
/// This package provides an Ollama-specific implementation of [LLMChatRepository]
/// with support for streaming chat, embeddings, tool calling, vision, and model management.
///
/// Example usage:
/// ```dart
/// import 'package:llm_ollama/llm_ollama.dart';
///
/// final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');
/// final stream = repo.streamChat('qwen3:0.6b', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
library;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Repositories
export 'src/ollama_chat_repository.dart';
export 'src/ollama_chat_repository_builder.dart';
export 'src/ollama_repository.dart';

// DTOs (for advanced usage)
export 'src/dto/ollama_model.dart';
export 'src/dto/ollama_response.dart';
export 'src/dto/ollama_embedding_response.dart';

