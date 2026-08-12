import 'package:llm_core/llm_core.dart';

/// Converts [LLMMessage] lists to the Anthropic Messages API format.
///
/// Key differences from OpenAI format:
/// - System messages are extracted into a separate top-level `system` field
/// - Content uses typed content blocks (text, image, tool_use, tool_result)
/// - Tool results appear as user messages with `tool_result` content blocks
class ClaudeMessageConverter {
  /// Converts a list of [LLMMessage] to Anthropic API format.
  ///
  /// Returns a record with:
  /// - `system`: optional system prompt string
  /// - `messages`: list of Anthropic-format message maps
  static ({String? system, List<Map<String, dynamic>> messages}) convert(
    List<LLMMessage> messages,
  ) {
    String? system;
    final systemParts = <String>[];
    final result = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LLMRole.system:
          if (msg.content != null) systemParts.add(msg.content!);
        case LLMRole.user:
          result.add(_convertUserMessage(msg));
        case LLMRole.assistant:
          result.add(_convertAssistantMessage(msg));
        case LLMRole.tool:
          // Tool results become a user message with tool_result content blocks
          final toolResult = _convertToolResultMessage(msg);
          // Merge with previous user message if it's also a tool_result batch
          if (result.isNotEmpty &&
              result.last['role'] == 'user' &&
              _isToolResultMessage(result.last)) {
            final existing =
                result.last['content'] as List<Map<String, dynamic>>;
            existing.addAll(
              toolResult['content'] as List<Map<String, dynamic>>,
            );
          } else {
            result.add(toolResult);
          }
      }
    }

    if (systemParts.isNotEmpty) {
      system = systemParts.join('\n\n');
    }

    return (system: system, messages: result);
  }

  static Map<String, dynamic> _convertUserMessage(LLMMessage msg) {
    final content = <Map<String, dynamic>>[];

    // Add images first
    if (msg.images != null) {
      for (final imageData in msg.images!) {
        content.add(_imageBlock(imageData));
      }
    }

    if (msg.content != null && msg.content!.isNotEmpty) {
      content.add({'type': 'text', 'text': msg.content!});
    }

    return {
      'role': 'user',
      // The API rejects a text block whose text is empty or whitespace-only,
      // so a message with no content gets a single space rather than ''.
      'content': content.isEmpty
          ? [
              {'type': 'text', 'text': ' '},
            ]
          : content,
    };
  }

  static Map<String, dynamic> _convertAssistantMessage(LLMMessage msg) {
    final content = <Map<String, dynamic>>[];

    if (msg.content != null && msg.content!.isNotEmpty) {
      content.add({'type': 'text', 'text': msg.content!});
    }

    if (msg.toolCalls != null) {
      for (final tc in msg.toolCalls!) {
        Map<String, dynamic> input;
        try {
          input = tc.argumentsJson;
        } catch (_) {
          input = {};
        }
        content.add({
          'type': 'tool_use',
          'id': tc.id ?? 'tool_${content.length}',
          'name': tc.name,
          'input': input,
        });
      }
    }

    return {
      'role': 'assistant',
      // The API rejects a text block whose text is empty or whitespace-only,
      // so a message with no content gets a single space rather than ''.
      'content': content.isEmpty
          ? [
              {'type': 'text', 'text': ' '},
            ]
          : content,
    };
  }

  static Map<String, dynamic> _convertToolResultMessage(LLMMessage msg) {
    final block = <String, dynamic>{
      'type': 'tool_result',
      'tool_use_id': msg.toolCallId ?? '',
    };
    if (msg.content != null) {
      block['content'] = msg.content;
    }
    // A failed tool must be reported as an error rather than as a successful
    // result whose text happens to describe a failure — otherwise the model
    // treats the error message as data.
    if (_looksLikeToolError(msg)) {
      block['is_error'] = true;
    }
    return {
      'role': 'user',
      'content': [block],
    };
  }

  /// Whether a tool-result message represents a failed execution.
  ///
  /// [LLMMessage] carries no dedicated failure flag, so this matches the
  /// message `StreamToolExecutor` produces when a tool throws:
  /// `'Tool <name> failed: <error>'` (see `llm_core/src/tool_executor.dart`).
  /// [LLMMessage.status] holds the tool name for executor-produced results,
  /// which makes the match specific rather than a loose substring test.
  static bool _looksLikeToolError(LLMMessage msg) {
    final content = msg.content;
    if (content == null) return false;
    final toolName = msg.status;
    if (toolName != null && toolName.isNotEmpty) {
      return content.startsWith('Tool $toolName failed:');
    }
    return RegExp(r'^Tool .+ failed:').hasMatch(content);
  }

  static bool _isToolResultMessage(Map<String, dynamic> msg) {
    if (msg['role'] != 'user') return false;
    final content = msg['content'];
    if (content is! List) return false;
    if (content.isEmpty) return false;
    return (content.first as Map<String, dynamic>)['type'] == 'tool_result';
  }

  static Map<String, dynamic> _imageBlock(String imageData) {
    // Detect MIME type from base64 prefix (data URI) or default to jpeg
    String mediaType = 'image/jpeg';
    String data = imageData;

    if (imageData.startsWith('data:')) {
      final commaIdx = imageData.indexOf(',');
      if (commaIdx != -1) {
        final header = imageData.substring(5, commaIdx);
        final semicolonIdx = header.indexOf(';');
        if (semicolonIdx != -1) {
          mediaType = header.substring(0, semicolonIdx);
        }
        data = imageData.substring(commaIdx + 1);
      }
    } else if (imageData.startsWith('/9j/')) {
      mediaType = 'image/jpeg';
    } else if (imageData.startsWith('iVBORw0KGgo')) {
      mediaType = 'image/png';
    } else if (imageData.startsWith('R0lGOD')) {
      mediaType = 'image/gif';
    } else if (imageData.startsWith('UklGR')) {
      mediaType = 'image/webp';
    }

    return {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': mediaType, 'data': data},
    };
  }
}
