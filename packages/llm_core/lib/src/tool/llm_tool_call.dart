/// Represents a tool call made by an LLM.
class LLMToolCall {
  LLMToolCall({required this.name, required this.arguments, required this.id});

  /// Unique identifier for this tool call (used by some providers like ChatGPT).
  final String? id;

  /// The name of the tool to call.
  final String name;

  /// The JSON-encoded arguments for the tool.
  final String arguments;
}
