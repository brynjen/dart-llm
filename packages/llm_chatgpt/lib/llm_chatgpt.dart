/// OpenAI/ChatGPT backend implementation for LLM interactions.
///
/// This package provides a ChatGPT-specific implementation of [LLMChatRepository]
/// with support for streaming chat, embeddings, and tool calling.
///
/// Example usage:
/// ```dart
/// import 'package:llm_chatgpt/llm_chatgpt.dart';
///
/// final repo = ChatGPTChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('gpt-4o', messages: [
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
export 'src/chatgpt_chat_repository.dart';
export 'src/chatgpt_chat_repository_builder.dart';

// DTOs (for advanced usage)
export 'src/dto/gpt_response.dart';
export 'src/dto/gpt_stream_decoder.dart';
export 'src/dto/gpt_embedding_response.dart';
