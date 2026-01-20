import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/tool/llm_tool_call.dart';

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

  /// Number of tokens in the prompt (only set on final chunk).
  final int? promptEvalCount;

  /// Number of tokens generated (only set on final chunk).
  final int? evalCount;

  /// Status is used in application to inform user about what is happening.
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
    this.images,
  });

  /// The text content of this chunk.
  final String? content;

  /// The thinking/reasoning content (for models that support it).
  final String? thinking;

  /// The role of the message sender.
  final LLMRole? role;

  /// ID for tool calls (if applicable).
  final String? toolCallId;

  /// Base64 images or URLs.
  final List<String>? images;

  /// List of tool call data.
  final List<LLMToolCall>? toolCalls;
}
