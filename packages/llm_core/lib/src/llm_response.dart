import 'tool/llm_tool_call.dart';

/// Represents a complete (non-streaming) response from an LLM.
class LLMResponse {
  LLMResponse({
    required this.model,
    required this.createdAt,
    required this.role,
    required this.content,
    required this.done,
    required this.doneReason,
    required this.promptEvalCount,
    required this.evalCount,
    required this.toolCalls,
  });

  /// The model that generated this response.
  final String model;

  /// When this response was created.
  final DateTime createdAt;

  /// The role of the responder (typically "assistant").
  final String role;

  /// The text content of the response.
  final String? content;

  /// Whether the response is complete.
  final bool done;

  /// The reason the response ended (e.g., "stop", "length", "tool_calls").
  final String doneReason;

  /// Number of tokens in the prompt.
  final int promptEvalCount;

  /// Number of tokens generated.
  final int evalCount;

  /// Tool calls requested by the model.
  final List<LLMToolCall>? toolCalls;
}

