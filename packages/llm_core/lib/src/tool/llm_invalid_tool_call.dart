import 'dart:convert';

/// A tool call the model emitted whose arguments cannot be decoded.
///
/// The OpenAI specification warns that the model "does not always generate
/// valid JSON" for function arguments, and a turn cut off by the token limit
/// ends mid-arguments by construction. Such a call is **never executable**,
/// but it is not dropped either: the caller needs to see what the model tried
/// to do. This follows LangChain's `invalid_tool_calls` and the Vercel AI
/// SDK's `invalid: true` tool calls, which surface the raw arguments together
/// with the parse error instead of discarding the call.
class LLMInvalidToolCall {
  /// Creates an invalid tool call.
  const LLMInvalidToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    required this.error,
  });

  /// Provider-assigned id, when the backend sent one.
  final String? id;

  /// The name of the tool the model tried to call.
  final String name;

  /// The raw argument text exactly as received, typically unterminated JSON.
  final String arguments;

  /// Why the arguments could not be decoded.
  final String error;

  /// Converts to OpenAI/Ollama API format for assistant message tool_calls.
  ///
  /// The arguments are replaced by `{}`. Echoing the raw text breaks the next
  /// request on servers that decode assistant tool-call arguments before
  /// applying the chat template (vLLM does), and the undecodable text carries
  /// nothing a model could act on. The tool error sent back alongside the call
  /// says what went wrong.
  Map<String, dynamic> toApiFormat() => {
    if (id != null && id!.isNotEmpty) 'id': id!,
    'type': 'function',
    'function': {'name': name, 'arguments': '{}'},
  };

  @override
  String toString() => jsonEncode({
    'id': id,
    'name': name,
    'arguments': arguments,
    'error': error,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LLMInvalidToolCall &&
          other.id == id &&
          other.name == name &&
          other.arguments == arguments &&
          other.error == error;

  @override
  int get hashCode => Object.hash(id, name, arguments, error);
}
