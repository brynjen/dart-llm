import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/stream_chat_options.dart';
import 'package:llm_core/src/llm_response.dart';
import 'package:llm_core/src/tool/llm_invalid_tool_call.dart';
import 'package:llm_core/src/tool/llm_tool_call.dart';
import 'package:llm_core/src/tool/llm_tool_call_delta.dart';
import 'package:llm_core/src/tool/llm_tool_result.dart';

/// Represents a streaming chunk from an LLM response.
///
/// Chunks are emitted incrementally as the model generates tokens.
class LLMChunk {
  LLMChunk({
    required this.model,
    required this.createdAt,
    required this.message,
    this.done,
    this.promptEvalCount,
    this.evalCount,
    this.usage,
    this.finishReason,
    this.providerMetadata = const {},
    this.status,
  });

  /// The model that generated this chunk.
  final String? model;

  /// Whether this is the final chunk in the stream.
  final bool? done;

  /// When this chunk was created.
  final DateTime? createdAt;

  /// The message content of this chunk.
  final LLMChunkMessage? message;

  /// Number of tokens in the prompt.
  ///
  /// Normally set only on the final chunk. With
  /// [LLMChatOptions.usagePerChunk] it is reported on every chunk.
  final int? promptEvalCount;

  /// Number of tokens generated so far.
  ///
  /// Normally set only on the final chunk, where it is the turn's total. With
  /// [LLMChatOptions.usagePerChunk] it is a **running** count reported on
  /// every chunk, so it must be read as the latest value rather than
  /// accumulated.
  final int? evalCount;

  /// First-class token usage metadata.
  ///
  /// Normally present only on the final chunk. With
  /// [LLMChatOptions.usagePerChunk] every chunk carries the provider's own
  /// running counters, which is what makes a measured tokens-per-second
  /// readout possible. Accumulating these would double-count; take the latest.
  final LLMUsage? usage;

  /// First-class finish reason metadata, usually present on the final chunk.
  final LLMFinishReason? finishReason;

  /// Provider-specific metadata that should be preserved but not standardized.
  final Map<String, dynamic> providerMetadata;

  /// Application-level display state, for example what a UI should show while
  /// a turn is in flight.
  ///
  /// [StreamToolExecutor] also sets it to the tool name on a tool-result chunk,
  /// which predates [LLMChunkMessage.toolName]. Read `message.toolName` for
  /// that; this stays populated for back-compat.
  final String? status;
}

/// The message portion of an LLM streaming chunk.
class LLMChunkMessage {
  LLMChunkMessage({
    required this.content,
    required this.role,
    this.thinking,
    this.toolCallId,
    this.toolCalls,
    this.invalidToolCalls,
    this.toolCallDeltas,
    this.images,
    this.rawContent,
    this.toolName,
    this.toolResult,
  });

  /// The text content of this chunk.
  final String? content;

  /// The thinking/reasoning content (for models that support it).
  final String? thinking;

  /// The role of the message sender.
  final LLMRole? role;

  /// ID for tool calls (if applicable).
  final String? toolCallId;

  /// For a tool-result chunk, the tool that produced it.
  ///
  /// Set by [StreamToolExecutor] alongside [toolCallId]. Consumers used to be
  /// told to build a `toolCallId` -> name map from earlier tool-call chunks to
  /// render "Tool X returned Y"; this removes that.
  final String? toolName;

  /// For a tool-result chunk, the structured outcome of the run.
  ///
  /// Carries the failure flag and any metadata the tool reported, so a caller
  /// can tell a failed run from a successful one without reading [content].
  final LLMToolResult? toolResult;

  /// Base64 images or URLs.
  final List<String>? images;

  /// List of tool call data.
  ///
  /// Only ever complete, executable calls. A call still being streamed appears
  /// on [toolCallDeltas] until the backend signals it is finished.
  final List<LLMToolCall>? toolCalls;

  /// Calls the model finished emitting whose arguments do not decode.
  ///
  /// Set on the same chunk as [toolCalls], at the end of a turn. Typical cause:
  /// the turn hit the token limit mid-arguments, in which case the chunk's
  /// finish reason is [LLMFinishReason.length]. These are never executed; see
  /// [LLMInvalidToolCall].
  final List<LLMInvalidToolCall>? invalidToolCalls;

  /// Fragments of tool calls that are still arriving.
  ///
  /// Backends that stream tool calls announce the tool's name in their first
  /// event and send the arguments in fragments afterwards. These deltas surface
  /// that progress as it happens, so a caller can show which tool is running
  /// without waiting for its arguments to finish.
  ///
  /// These are **never executable** — an argument fragment is part of a JSON
  /// document that only parses once all fragments are concatenated. The
  /// finished call arrives at the end of the call on [toolCalls], or on
  /// [invalidToolCalls] when its concatenated arguments do not decode.
  ///
  /// A backend that delivers a whole tool call in a single event emits no
  /// deltas at all. That is not a gap: it has no partial state to report, and
  /// its [toolCalls] already arrive as early as anything could.
  final List<LLMToolCallDelta>? toolCallDeltas;

  /// The assistant turn exactly as the model emitted it, including any
  /// tool-call markup that was stripped out of [content].
  ///
  /// Only set on the final chunk of a turn, and only by backends that parse tool
  /// calls out of raw model output — that is, local inference. Hosted APIs return
  /// tool calls as structured fields and have nothing to preserve here.
  ///
  /// Callers that keep their own conversation history need this to replay the
  /// turn faithfully: a model that is shown its earlier tool call, followed by
  /// the tool result, will keep using tools. Replaying only the visible text
  /// instead shows the model a turn where it announced a tool and then answered
  /// without calling one, and it will copy that.
  final String? rawContent;
}
