/// Google Gemini API backend for LLM interactions.
///
/// Provides a Gemini-specific implementation of [LLMChatRepository]
/// with support for streaming chat, embeddings, and tool calling via the Gemini API.
///
/// Example usage:
/// ```dart
/// import 'package:llm_gemini/llm_gemini.dart';
///
/// final repo = GeminiChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('gemini-2.0-flash', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
library;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Repository
export 'src/gemini_chat_repository.dart';
export 'src/gemini_chat_repository_builder.dart';

// DTOs (for advanced usage)
export 'src/dto/gemini_chunk.dart';
export 'src/dto/gemini_usage.dart';
export 'src/dto/gemini_embedding_response.dart';
