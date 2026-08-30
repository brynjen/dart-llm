import 'dart:convert';

/// Represents a tool call made by an LLM.
class LLMToolCall {
  /// Creates a typed tool call.
  LLMToolCall({required this.name, required this.arguments, required this.id});

  /// Creates a tool call from an OpenAI/Ollama-style API object.
  factory LLMToolCall.fromApiFormat(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>? ?? const {};
    final rawArguments = function['arguments'];
    return LLMToolCall(
      id: json['id'] as String?,
      name: function['name'] as String? ?? '',
      arguments: rawArguments is String
          ? rawArguments
          : jsonEncode(rawArguments ?? const <String, dynamic>{}),
    );
  }

  /// Normalizes old map-shaped calls and new typed calls into [LLMToolCall].
  factory LLMToolCall.from(Object value) {
    if (value is LLMToolCall) return value;
    if (value is Map<String, dynamic>) return LLMToolCall.fromApiFormat(value);
    if (value is Map) {
      return LLMToolCall.fromApiFormat(Map<String, dynamic>.from(value));
    }
    throw ArgumentError.value(value, 'value', 'Unsupported tool call value');
  }

  /// Unique identifier for this tool call (used by some providers like ChatGPT).
  final String? id;

  /// The name of the tool to call.
  final String name;

  /// The JSON-encoded arguments for the tool.
  final String arguments;

  /// Converts to OpenAI/Ollama API format for assistant message tool_calls.
  Map<String, dynamic> toApiFormat() => {
    if (id != null && id!.isNotEmpty) 'id': id!,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };

  /// Alias for APIs and tests that expect JSON conversion.
  Map<String, dynamic> toJson() => toApiFormat();

  /// Decodes [arguments] as a JSON object.
  ///
  /// A tool that takes no parameters is routinely called with no arguments at
  /// all: OpenAI-compatible servers send `""` and Anthropic simply never emits
  /// a fragment to concatenate. That is a call with no arguments, not
  /// malformed JSON, so it decodes to an empty map rather than throwing. A
  /// literal `null` is treated the same way.
  Map<String, dynamic> get argumentsJson {
    final trimmed = arguments.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded == null) return <String, dynamic>{};
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Tool call arguments must decode to an object');
  }

  @override
  String toString() => jsonEncode(toApiFormat());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LLMToolCall &&
          other.id == id &&
          other.name == name &&
          other.arguments == arguments;

  @override
  int get hashCode => Object.hash(id, name, arguments);
}
