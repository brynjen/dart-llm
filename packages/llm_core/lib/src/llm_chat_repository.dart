import 'package:llm_core/src/llm_chunk.dart';
import 'package:llm_core/src/llm_capabilities.dart';
import 'package:llm_core/src/llm_embedding.dart';
import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/llm_response.dart';
import 'package:llm_core/src/stream_chat_options.dart';
import 'package:llm_core/src/tool/llm_invalid_tool_call.dart';
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
  /// **Cancellation:**
  /// Cancelling the subscription aborts the generation. The in-flight request
  /// is aborted and its socket closed, so an OpenAI-compatible server stops
  /// generating rather than finishing the turn into a listener that has gone
  /// away. `cancel()` completes promptly and does not throw.
  ///
  /// Cancel through a subscription, not an `await for` loop, which cannot be
  /// interrupted from outside:
  ///
  /// ```dart
  /// final subscription = repo.streamChat(model, messages: messages).listen(render);
  /// // ...on user interrupt:
  /// await subscription.cancel();
  /// ```
  ///
  /// Two things it does not cover. A tool already executing runs to completion,
  /// because its `Future` belongs to the caller, not to this stream. And an
  /// in-process backend has no request to abort — `llm_llamacpp` yields per
  /// token, so a cancel lands within one decode step instead.
  ///
  /// Implementations are not required to support this, and the interface is
  /// unchanged, so existing implementations keep working; an HTTP client that
  /// ignores `http.Abortable` degrades to ending when the response does.
  ///
  /// **Returns:**
  /// A [Stream<LLMChunk>] that emits chunks as tokens are generated.
  /// Each chunk contains:
  /// - `message.content` - Partial text content (accumulate to get full response)
  /// - `message.thinking` - Thinking/reasoning content (if `think: true`)
  /// - `message.toolCalls` - Tool calls requested by the model
  /// - `message.invalidToolCalls` - Finished tool calls whose arguments do not
  ///   decode (never executed; usually a turn cut off at the token limit)
  /// - `message.toolCallDeltas` - Fragments of tool calls still streaming
  /// - `finishReason` - Why the turn ended (on the final chunk)
  /// - `done` - Whether this is the final chunk
  /// - `promptEvalCount` - Number of tokens in the prompt (only on final chunk)
  /// - `evalCount` - Number of tokens generated (only on final chunk)
  ///
  /// **Tool Calling:**
  /// When tools are provided and the model requests them, the method automatically
  /// (unless `LLMChatOptions.autoExecuteTools` is false):
  /// 1. Executes the requested tools; each invalid call is answered with a tool
  ///    error instead of being run
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
  /// - `invalidToolCalls` - Final tool calls whose arguments do not decode
  /// - `finishReason` - Why the response ended
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
    List<LLMInvalidToolCall>? finalInvalidToolCalls;
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
    // Tool calls carried by the turn currently being read. Several backends
    // deliver complete calls on a chunk with `done: false` — Ollama's native
    // API puts them on the frame before the terminal one, Claude and Gemini
    // emit them ahead of their own terminal chunk — so keying off `done`
    // alone lost them entirely for those three.
    final pendingToolCalls = <LLMToolCall>[];
    final pendingInvalidToolCalls = <LLMInvalidToolCall>[];
    var turnClosed = false;

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
        // A tool-result chunk means the loop executed the calls that preceded
        // it, so they are not this response's outstanding calls. `sawToolLoop`
        // above keys off the same signal.
        if (chunk.message!.role == LLMRole.tool) {
          pendingToolCalls.clear();
          pendingInvalidToolCalls.clear();
          finalToolCalls = null;
          finalInvalidToolCalls = null;
          turnClosed = false;
        }

        // A new turn's first assistant payload retires the previous turn's
        // calls. This cannot be done at the `done` chunk itself: a turn can
        // end with several `done` frames (see the token-count fold below), and
        // a trailing usage-only frame would then wipe calls that were real.
        final message = chunk.message!;
        final carriesAssistantPayload =
            message.role == LLMRole.assistant &&
            (message.content != null ||
                message.thinking != null ||
                message.toolCalls != null ||
                message.invalidToolCalls != null ||
                message.toolCallDeltas != null);
        if (turnClosed && carriesAssistantPayload) {
          // `finalToolCalls` goes too: the promoted calls belonged to the turn
          // that just ended, and a turn is now under way that will end the
          // response instead. Backends running their own tool loop (llama.cpp)
          // emit no tool-role chunk, so this is the only boundary signal.
          pendingToolCalls.clear();
          pendingInvalidToolCalls.clear();
          finalToolCalls = null;
          finalInvalidToolCalls = null;
          turnClosed = false;
        }

        if (message.toolCalls?.isNotEmpty ?? false) {
          pendingToolCalls.addAll(message.toolCalls!);
        }
        if (message.invalidToolCalls?.isNotEmpty ?? false) {
          pendingInvalidToolCalls.addAll(message.invalidToolCalls!);
        }

        if ((chunk.done ?? false) &&
            chunk.message!.role == LLMRole.assistant &&
            (chunk.message!.toolCalls == null ||
                chunk.message!.toolCalls!.isEmpty) &&
            (chunk.message!.invalidToolCalls == null ||
                chunk.message!.invalidToolCalls!.isEmpty)) {
          sawFinalAssistantAnswer = true;
        }
      }

      if (chunk.done ?? false) {
        sawDoneChunk = true;
        turnClosed = true;
        // Assigned only when non-empty so a trailing usage-only `done` frame
        // cannot erase the calls the turn actually carried.
        if (pendingToolCalls.isNotEmpty) {
          finalToolCalls = List<LLMToolCall>.unmodifiable(pendingToolCalls);
        }
        if (pendingInvalidToolCalls.isNotEmpty) {
          finalInvalidToolCalls = List<LLMInvalidToolCall>.unmodifiable(
            pendingInvalidToolCalls,
          );
        }
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

    // Backstop for any backend that did not classify the turn itself, so
    // `finishReason` can never contradict `toolCalls` on the way out.
    final resolvedFinishReason = LLMFinishReason.resolve(
      reported: finishReason,
      hasCompleteToolCalls: finalToolCalls?.isNotEmpty ?? false,
    );

    return LLMResponse(
      model: responseModel ?? model,
      createdAt: createdAt ?? DateTime.now(),
      role: 'assistant',
      content: content,
      thinking: thinking,
      done: true,
      doneReason: resolvedFinishReason?.providerName ?? doneReason ?? 'stop',
      promptEvalCount: promptEvalCount ?? usage?.promptTokens ?? 0,
      evalCount: evalCount ?? usage?.completionTokens ?? 0,
      usage: usage,
      finishReason: resolvedFinishReason,
      providerMetadata: providerMetadata,
      toolCalls: finalToolCalls,
      invalidToolCalls: finalInvalidToolCalls,
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
