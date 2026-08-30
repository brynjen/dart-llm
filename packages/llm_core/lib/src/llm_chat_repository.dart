import 'package:llm_core/src/llm_chunk.dart';
import 'package:llm_core/src/llm_capabilities.dart';
import 'package:llm_core/src/llm_embedding.dart';
import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/llm_response.dart';
import 'package:llm_core/src/stream_chat_options.dart';
import 'package:llm_core/src/tool/llm_tool.dart';
import 'package:llm_core/src/tool/llm_tool_call.dart';
import 'package:llm_core/src/validation.dart';

/// Abstract repository interface for LLM chat operations.
///
/// Implement this interface to create backends for different LLM providers
/// (e.g., Ollama, ChatGPT, llama.cpp).
abstract class LLMChatRepository {
  /// Streams a chat response from the LLM.
  ///
  /// This method streams tokens as they are generated, allowing for real-time
  /// display of responses. The stream includes content chunks, tool calls, and
  /// metadata.
  ///
  /// **Parameters:**
  /// - [model] - The model identifier to use (e.g., 'gpt-4o', 'qwen3:0.6b').
  ///   Must be a non-empty string.
  /// - [messages] - The conversation history. Must contain at least one message.
  ///   Messages should follow the conversation flow (user, assistant, system, tool).
  /// - [think] - Whether to request thinking/reasoning output (if supported by the model).
  ///   Defaults to `false`. Only supported by some models (e.g., Ollama with thinking models).
  /// - [tools] - Optional list of tools the model can use for function calling.
  ///   Tools are executed automatically when the model requests them.
  /// - [extra] - Additional context to pass to tool executions. Can be any type.
  ///   Useful for passing user context, session data, etc. to tool implementations.
  /// - [options] - Optional [StreamChatOptions] to encapsulate all options.
  ///   If provided, takes precedence over individual parameters.
  ///
  /// **Returns:**
  /// A [Stream<LLMChunk>] that emits chunks as tokens are generated.
  /// Each chunk contains:
  /// - `message.content` - Partial text content (accumulate to get full response)
  /// - `message.thinking` - Thinking/reasoning content (if `think: true`)
  /// - `message.toolCalls` - Tool calls requested by the model
  /// - `done` - Whether this is the final chunk
  /// - `promptEvalCount` - Number of tokens in the prompt (only on final chunk)
  /// - `evalCount` - Number of tokens generated (only on final chunk)
  ///
  /// **Tool Calling:**
  /// When tools are provided and the model requests them, the method automatically:
  /// 1. Executes the requested tools
  /// 2. Adds tool results to the conversation
  /// 3. Continues the conversation with the tool results
  /// 4. Repeats until a final response (no more tool calls) is received
  ///
  /// **Example:**
  /// ```dart
  /// final stream = repo.streamChat('gpt-4o', messages: [
  ///   LLMMessage(role: LLMRole.user, content: 'What is 2+2?')
  /// ], tools: [CalculatorTool()]);
  ///
  /// String fullResponse = '';
  /// await for (final chunk in stream) {
  ///   if (chunk.message?.content != null) {
  ///     fullResponse += chunk.message!.content!;
  ///     print(chunk.message!.content!); // Print as it streams
  ///   }
  ///   if (chunk.done == true) {
  ///     print('Total tokens: ${chunk.evalCount}');
  ///   }
  /// }
  /// ```
  ///
  /// **Throws:**
  /// - [LLMApiException] if validation fails or the API request fails
  /// - [ThinkingNotSupportedException] if `think: true` but model doesn't support it
  /// - [ToolsNotSupportedException] if tools are provided but model doesn't support them
  /// - [VisionNotSupportedException] if images are provided but model doesn't support vision
  ///
  /// Implementations should call [Validation.validateModelName] and
  /// [Validation.validateMessages] at the start of their implementation.
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,

    /// The tools this message should use.
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  });

  /// Reports repository/model capabilities.
  ///
  /// Providers may override this with model-aware logic. The default reflects
  /// the core repository surface rather than provider guarantees.
  LLMCapabilities capabilitiesForModel(String model) {
    return const LLMCapabilities();
  }

  /// Generates a complete (non-streaming) chat response from the LLM.
  ///
  /// This method collects all chunks internally and returns the complete response.
  /// It handles the full tool execution loop, executing tools and continuing the
  /// conversation until a final response is received.
  ///
  /// **Parameters:**
  /// - [model] - The model identifier to use (e.g., 'gpt-4o', 'qwen3:0.6b').
  /// - [messages] - The conversation history. Must contain at least one message.
  /// - [think] - Whether to request thinking/reasoning output (if supported).
  /// - [tools] - Optional list of tools the model can use for function calling.
  /// - [extra] - Additional context to pass to tool executions.
  /// - [options] - Optional [StreamChatOptions] to encapsulate all options.
  ///
  /// **Returns:**
  /// A [Future<LLMResponse>] containing:
  /// - `content` - The complete text response (after all tool calls are executed)
  /// - `toolCalls` - Any final tool calls (if the response ended with tool calls)
  /// - `promptEvalCount` - Number of tokens in the prompt
  /// - `evalCount` - Number of tokens generated
  /// - `doneReason` - Reason the response ended (e.g., 'stop', 'length', 'tool_calls')
  ///
  /// **Tool Execution:**
  /// This method automatically handles the complete tool execution loop:
  /// 1. Sends the request with tools
  /// 2. If the model requests tools, executes them
  /// 3. Continues the conversation with tool results
  /// 4. Repeats until a final response (no more tool calls) is received
  /// 5. Returns the complete response
  ///
  /// **Use Cases:**
  /// - Agentic workflows where you need the full response before passing to the next agent
  /// - Batch processing where streaming is not needed
  /// - Simple request-response patterns
  ///
  /// **Example:**
  /// ```dart
  /// final response = await repo.chatResponse('gpt-4o', messages: [
  ///   LLMMessage(role: LLMRole.user, content: 'What is 2+2?')
  /// ], tools: [CalculatorTool()]);
  ///
  /// print(response.content); // "2+2 equals 4"
  /// print('Tokens used: ${response.evalCount}');
  /// // All tool calls have been executed internally
  /// ```
  ///
  /// **Throws:**
  /// - [LLMApiException] if validation fails or the API request fails
  /// - [ThinkingNotSupportedException] if `think: true` but model doesn't support it
  /// - [ToolsNotSupportedException] if tools are provided but model doesn't support them
  /// - [VisionNotSupportedException] if images are provided but model doesn't support vision
  Future<LLMResponse> chatResponse(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  }) async {
    // Validate inputs
    Validation.validateModelName(model);
    Validation.validateMessages(messages);
    // Default implementation: collect chunks from streamChat
    // The tool execution loop is already handled in streamChat for each backend
    String? content;
    String? thinking;
    List<LLMToolCall>? finalToolCalls;
    int? promptEvalCount;
    int? evalCount;
    String? doneReason;
    LLMUsage? usage;
    LLMFinishReason? finishReason;
    var providerMetadata = const <String, dynamic>{};
    String? responseModel;
    DateTime? createdAt;
    var sawToolLoop = false;
    var sawFinalAssistantAnswer = false;
    var sawDoneChunk = false;

    await for (final chunk in streamChat(
      model,
      messages: messages,
      think: think,
      tools: tools,
      extra: extra,
      options: options,
    )) {
      responseModel ??= chunk.model;
      createdAt ??= chunk.createdAt ?? DateTime.now();

      if (chunk.message != null) {
        if (chunk.message!.role == LLMRole.tool) {
          sawToolLoop = true;
          sawFinalAssistantAnswer = false;
        }

        if (chunk.message!.role == LLMRole.assistant &&
            chunk.message!.content != null) {
          content = (content ?? '') + (chunk.message!.content ?? '');
          if (sawToolLoop &&
              (chunk.message!.toolCalls == null ||
                  chunk.message!.toolCalls!.isEmpty)) {
            sawFinalAssistantAnswer = true;
          }
        }
        if (chunk.message!.role == LLMRole.assistant &&
            chunk.message!.thinking != null) {
          thinking = (thinking ?? '') + (chunk.message!.thinking ?? '');
          if (sawToolLoop &&
              (chunk.message!.toolCalls == null ||
                  chunk.message!.toolCalls!.isEmpty)) {
            sawFinalAssistantAnswer = true;
          }
        }
        // Only capture tool calls from the final response (when done is true)
        if ((chunk.done ?? false) && chunk.message!.toolCalls != null) {
          finalToolCalls = chunk.message!.toolCalls;
        }

        if ((chunk.done ?? false) &&
            chunk.message!.role == LLMRole.assistant &&
            (chunk.message!.toolCalls == null ||
                chunk.message!.toolCalls!.isEmpty)) {
          sawFinalAssistantAnswer = true;
        }
      }

      if (chunk.done ?? false) {
        sawDoneChunk = true;
        // A turn can end with more than one `done` chunk — several backends
        // report the finish reason first and token counts in a trailing
        // usage-only frame, and a tool loop produces a done chunk per round.
        // Assigning unconditionally let a later count-less chunk erase counts
        // that had already arrived, so these fold the same way `usage` does.
        promptEvalCount = chunk.promptEvalCount ?? promptEvalCount;
        evalCount = chunk.evalCount ?? evalCount;
        usage = chunk.usage ?? usage;
        finishReason = chunk.finishReason ?? finishReason;
        providerMetadata = chunk.providerMetadata.isNotEmpty
            ? chunk.providerMetadata
            : providerMetadata;
        doneReason = chunk.finishReason?.providerName ?? doneReason ?? 'stop';
      }
    }

    if (sawToolLoop && !sawFinalAssistantAnswer) {
      throw ToolLoopIncompleteException(
        reason:
            'chatResponse finished without a final assistant answer after tool loop',
        attemptsUsed: 0,
        attemptsRemaining: 0,
        lastRoundEndedWithDone: sawDoneChunk,
        lastRoundHadToolCalls: sawToolLoop,
        hadFinalAssistantResponse: false,
      );
    }

    return LLMResponse(
      model: responseModel ?? model,
      createdAt: createdAt ?? DateTime.now(),
      role: 'assistant',
      content: content,
      thinking: thinking,
      done: true,
      doneReason: doneReason ?? 'stop',
      promptEvalCount: promptEvalCount ?? usage?.promptTokens ?? 0,
      evalCount: evalCount ?? usage?.completionTokens ?? 0,
      usage: usage,
      finishReason: finishReason,
      providerMetadata: providerMetadata,
      toolCalls: finalToolCalls,
    );
  }

  /// Generates embeddings for the given texts.
  ///
  /// Embeddings are vector representations of text that can be used for semantic
  /// search, similarity comparison, and other machine learning tasks.
  ///
  /// **Parameters:**
  /// - [model] - The embedding model to use (e.g., 'text-embedding-3-small', 'nomic-embed-text').
  ///   Must be a model that supports embeddings.
  /// - [messages] - The texts to embed. Each string will be converted to an embedding vector.
  ///   Must not be empty.
  /// - [options] - Additional model-specific options. Format depends on the backend:
  ///   - Ollama: Options are passed directly to the API
  ///   - ChatGPT: Currently unused (OpenAI API doesn't support additional options)
  ///   - llama.cpp: Currently unused
  ///
  /// **Returns:**
  /// A [Future<List<LLMEmbedding>>] containing one embedding per input message.
  /// Each embedding contains:
  /// - `embedding` - The embedding vector as a list of doubles
  /// - `model` - The model that generated the embedding
  /// - `promptEvalCount` - Number of tokens in the input text
  ///
  /// **Example:**
  /// ```dart
  /// final embeddings = await repo.embed(
  ///   model: 'text-embedding-3-small',
  ///   messages: ['Hello world', 'Goodbye world'],
  /// );
  ///
  /// print('Embedding dimension: ${embeddings[0].embedding.length}');
  /// print('First embedding: ${embeddings[0].embedding.take(5).toList()}');
  /// ```
  ///
  /// **Throws:**
  /// - [LLMApiException] if the API request fails
  /// - [UnsupportedError] if embeddings are not supported by the backend
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  });

  /// Generates embeddings for multiple texts in a single call.
  ///
  /// Use this method when embedding many texts at once; providers may optimize
  /// batch requests (e.g. one HTTP request). Same semantics as [embed] for
  /// the given [model], [messages], and [options].
  ///
  /// **Provider behaviour:**
  /// - **Ollama**: Passes array to `input`; see [Embeddings](https://docs.ollama.com/capabilities/embeddings).
  /// - **OpenAI/ChatGPT**: `input` as array of strings (max 2048, 300k tokens total); see [Create embeddings](https://platform.openai.com/docs/api-reference/embeddings).
  /// - **llama.cpp**: Processes each message in sequence (or via server batch when using HTTP).
  ///
  /// **Returns:**
  /// A [Future<List<LLMEmbedding>>] with one embedding per element of [messages],
  /// in the same order.
  ///
  /// **Throws:**
  /// - [LLMApiException] if the API request fails
  /// - [UnsupportedError] if embeddings are not supported by the backend
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    return embed(model: model, messages: messages, options: options);
  }
}
