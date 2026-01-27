import 'package:llm_core/llm_core.dart';

/// Converts LLM messages to Ollama API format.
class OllamaMessageConverter {
  /// Converts an LLMMessage to Ollama's JSON format.
  ///
  /// Ollama format:
  /// - role: string (user, system, assistant, tool)
  /// - content: string
  /// - tool_call_id: string (optional, for tool messages)
  /// - tool_calls: array (optional, for assistant messages with tool calls)
  /// - images: array of base64 strings (optional, for vision)
  static Map<String, dynamic> toJson(LLMMessage message) {
    final json = <String, dynamic>{
      'role': message.role.name,
      'content': message.content ?? '',
    };

    if (message.toolCallId != null) {
      json['tool_call_id'] = message.toolCallId;
    }
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      json['tool_calls'] = message.toolCalls;
    }
    if (message.images != null && message.images!.isNotEmpty) {
      json['images'] = message.images;
    }

    return json;
  }
}
