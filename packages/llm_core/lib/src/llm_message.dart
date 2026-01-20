/// Represents a message in an LLM conversation.
class LLMMessage {
  LLMMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls,
    this.images,
    this.status,
  });

  /// The text content of the message.
  final String? content;

  /// The role of the message sender.
  final LLMRole role;

  /// ID for tool call responses (used by some providers like ChatGPT).
  final String? toolCallId;

  /// Base64 encoded images or URLs for vision-capable models.
  final List<String>? images;

  /// List of tool calls made by the assistant.
  final List<Map<String, dynamic>>? toolCalls;

  /// Status is used in application to inform user about what is happening.
  final String? status;

  /// Converts this message to a JSON map suitable for API requests.
  ///
  /// Note: This produces a format compatible with OpenAI's API.
  /// Backend-specific repositories may override or transform this.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role.name};
    switch (role) {
      case LLMRole.user:
        final content = <Map<String, dynamic>>[];
        if (this.content != null) {
          content.add({'type': 'text', 'text': this.content});
        }
        for (final img in images ?? <String>[]) {
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,$img'},
          });
        }
        json['content'] = content;
        break;
      default:
        json['content'] = content;
        break;
    }
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls;
    }
    return json;
  }
}

/// The role of a message participant in an LLM conversation.
enum LLMRole {
  /// Messages from the user.
  user,

  /// System prompt for the LLM.
  system,

  /// Message the LLM has sent.
  assistant,

  /// Result from a tool execution.
  tool,
}
