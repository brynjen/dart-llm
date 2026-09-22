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

  /// Stands in for a message that converts to no content blocks at all.
  ///
  /// Anthropic is the only backend here with no valid representation of an
  /// empty message: `content: ''`, `content: []`, an empty text block and a
  /// whitespace-only text block are each rejected, as is an empty `messages`
  /// array. Every other backend accepts one, so dropping the message instead
  /// would make the same conversation fail on Claude alone.
  static const _emptyContentPlaceholder = [
    {'type': 'text', 'text': '.'},
  ];

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
      // The Messages API rejects a text block whose text is empty or
      // whitespace-only — `TextBlockParam.text` is `minLength: 1`, and an
      // all-whitespace block fails separately with "text content blocks must
      // contain non-whitespace text". A single space satisfies neither, so the
      // placeholder has to carry a non-whitespace character.
      'content': content.isEmpty ? _emptyContentPlaceholder : content,
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
      // The Messages API rejects a text block whose text is empty or
      // whitespace-only — `TextBlockParam.text` is `minLength: 1`, and an
      // all-whitespace block fails separately with "text content blocks must
      // contain non-whitespace text". A single space satisfies neither, so the
      // placeholder has to carry a non-whitespace character.
      'content': content.isEmpty ? _emptyContentPlaceholder : content,
    };
  }

  static Map<String, dynamic> _convertToolResultMessage(LLMMessage msg) {
    final block = <String, dynamic>{
      'type': 'tool_result',
      'tool_use_id': msg.toolCallId ?? '',
    };
    // Anthropic accepts `content` as a string or as a list of text/image/
    // document/search_result blocks, so a tool that returned an image hands
    // back the image itself rather than a description of it. Text-only
    // providers fall back to `LLMToolResult.content`; here the richer form
    // wins when the tool supplied one.
    final parts = msg.toolResult?.contentParts ?? const <LLMMessageContent>[];
    if (parts.isNotEmpty) {
      block['content'] = [
        for (final part in parts)
          switch (part) {
            LLMTextContent(:final text) => {'type': 'text', 'text': text},
            LLMImageContent() => _imageBlock(part.imageUrl),
          },
      ];
    } else if (msg.content != null) {
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
  /// [LLMToolResult.isError] is authoritative when present, which is the whole
  /// point of that type: this used to decide by matching the text
  /// `'Tool <name> failed: <error>'` that `StreamToolExecutor` produced, and
  /// that was wrong twice over. A call rejected for undecodable arguments is
  /// reported as `'Tool <name> was not called: …'`, which the pattern misses,
  /// so a parse error reached the model without `is_error` and was read as
  /// data. And a *successful* tool whose output happened to start that way was
  /// flagged as a failure.
  ///
  /// The text match remains as a fallback for messages this package did not
  /// build — a caller-assembled history, or one serialized before
  /// [LLMMessage.toolResult] existed. [LLMMessage.toolName] names the tool
  /// there, falling back to [LLMMessage.status], which carried it before.
  static bool _looksLikeToolError(LLMMessage msg) {
    final result = msg.toolResult;
    if (result != null) return result.isError;

    final content = msg.content;
    if (content == null) return false;
    final toolName = msg.toolName ?? msg.status;
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
