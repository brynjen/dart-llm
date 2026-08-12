import 'package:llm_core/llm_core.dart';

/// Converts LLM messages to Ollama API format.
class OllamaMessageConverter {
  /// Converts a list of LLMMessages to Ollama's JSON format.
  ///
  /// List-aware conversion is required for tool messages: Ollama expects
  /// [tool_name] for tool role messages, which we derive from the preceding
  /// assistant message's tool_calls by matching [toolCallId].
  ///
  /// Ollama format:
  /// - role: string (user, system, assistant, tool)
  /// - content: string
  /// - tool_name: string (for tool messages; derived from context)
  /// - tool_call_id: string (for tool messages; OpenAI compatibility)
  /// - tool_calls: array (optional, for assistant messages with tool calls)
  /// - images: array of base64 strings (optional, for vision)
  static List<Map<String, dynamic>> messagesToOllamaJson(
    List<LLMMessage> messages,
  ) {
    return messages
        .asMap()
        .entries
        .map((e) => _toJson(e.value, messages, e.key))
        .toList(growable: false);
  }

  static Map<String, dynamic> _toJson(
    LLMMessage message,
    List<LLMMessage> allMessages,
    int index,
  ) {
    final json = <String, dynamic>{
      'role': message.role.name,
      'content': message.content ?? '',
    };

    if (message.role == LLMRole.tool && message.toolCallId != null) {
      json['tool_call_id'] = message.toolCallId;
      final toolName = _deriveToolName(message.toolCallId!, allMessages, index);
      if (toolName != null && toolName.isNotEmpty) {
        json['tool_name'] = toolName;
      }
    }
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      json['tool_calls'] = _convertToolCallsForOllama(message.toolCalls!);
    }
    if (message.images != null && message.images!.isNotEmpty) {
      json['images'] = message.images;
    }

    return json;
  }

  /// Derives tool_name from toolCallId using the fallback chain:
  /// 1. Look up in preceding assistant's tool_calls by id
  /// 2. Parse synthetic ID format tool_${index}_${name}
  /// 3. Return null (caller sends tool_call_id only; Ollama accepts it)
  static String? _deriveToolName(
    String toolCallId,
    List<LLMMessage> messages,
    int toolMessageIndex,
  ) {
    // Primary: look up in preceding assistant's tool_calls
    for (var i = toolMessageIndex - 1; i >= 0; i--) {
      final prev = messages[i];
      if (prev.role == LLMRole.assistant &&
          prev.toolCalls != null &&
          prev.toolCalls!.isNotEmpty) {
        for (final tc in prev.toolCalls!) {
          if (tc.id == toolCallId) {
            if (tc.name.isNotEmpty) return tc.name;
            return null;
          }
        }
        return null; // Found assistant but no matching id
      }
    }

    // Fallback: parse synthetic ID tool_${index}_${name}
    final match = RegExp(r'^tool_\d+_(.+)$').firstMatch(toolCallId);
    return match?.group(1);
  }

  /// Converts tool_calls for Ollama: arguments must be object, not string.
  static List<Map<String, dynamic>> _convertToolCallsForOllama(
    List<LLMToolCall> toolCalls,
  ) {
    return toolCalls.asMap().entries.map((entry) {
      final i = entry.key;
      final tc = entry.value;
      final result = <String, dynamic>{'type': 'function'};
      result['function'] = {
        'index': i,
        'name': tc.name,
        'arguments': tc.argumentsJson,
      };
      if (tc.id != null) result['id'] = tc.id;
      return result;
    }).toList();
  }
}
