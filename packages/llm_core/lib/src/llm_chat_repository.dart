import 'llm_chunk.dart';
import 'llm_embedding.dart';
import 'llm_message.dart';
import 'tool/llm_tool.dart';

/// Abstract repository interface for LLM chat operations.
///
/// Implement this interface to create backends for different LLM providers
/// (e.g., Ollama, ChatGPT, llama.cpp).
abstract class LLMChatRepository {
  /// Streams a chat response from the LLM.
  ///
  /// [model] - The model identifier to use.
  /// [messages] - The conversation history.
  /// [think] - Whether to request thinking/reasoning output (if supported).
  /// [tools] - Optional list of tools the model can use.
  /// [extra] - Additional context to pass to tool executions.
  ///
  /// Returns a stream of [LLMChunk]s as the model generates tokens.
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,

    /// The tools this message should use.
    List<LLMTool> tools = const [],
    dynamic extra,
  });

  /// Generates embeddings for the given texts.
  ///
  /// [model] - The embedding model to use.
  /// [messages] - The texts to embed.
  /// [options] - Additional model-specific options.
  ///
  /// Returns a list of [LLMEmbedding]s, one per input message.
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  });
}

