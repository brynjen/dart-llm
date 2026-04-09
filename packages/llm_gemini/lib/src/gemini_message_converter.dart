import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Converts [LLMMessage] lists to the Gemini API format.
///
/// Key differences from OpenAI format:
/// - System messages become a top-level `systemInstruction` field
/// - Uses `contents` array with `role: "user"` or `role: "model"` (not "assistant")
/// - Content is structured as `parts` arrays
/// - Tool calls are `functionCall` parts; tool results are `functionResponse` parts
/// - Consecutive tool results are merged into a single user content entry
class GeminiMessageConverter {
  /// Converts a list of [LLMMessage] to the Gemini API request fields.
  ///
  /// Returns a record with:
  /// - `systemInstruction`: optional system instruction map
  /// - `contents`: list of Gemini-format content maps
  static ({
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> contents,
  })
  convert(List<LLMMessage> messages) {
    Map<String, dynamic>? systemInstruction;
    final systemParts = <String>[];
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LLMRole.system:
          if (msg.content != null) systemParts.add(msg.content!);
        case LLMRole.user:
          contents.add(_convertUserMessage(msg));
        case LLMRole.assistant:
          contents.add(_convertAssistantMessage(msg));
        case LLMRole.tool:
          // Tool results become user contents with functionResponse parts
          final toolContent = _convertToolResultMessage(msg);
          // Merge consecutive tool responses into one user content
          if (contents.isNotEmpty &&
              contents.last['role'] == 'user' &&
              _isFunctionResponseContent(contents.last)) {
            final existing =
                contents.last['parts'] as List<Map<String, dynamic>>;
            existing.addAll(toolContent['parts'] as List<Map<String, dynamic>>);
          } else {
            contents.add(toolContent);
          }
      }
    }

    if (systemParts.isNotEmpty) {
      systemInstruction = {
        'parts': [
          {'text': systemParts.join('\n\n')},
        ],
      };
    }

    return (systemInstruction: systemInstruction, contents: contents);
  }

  static Map<String, dynamic> _convertUserMessage(LLMMessage msg) {
    final parts = <Map<String, dynamic>>[];

    if (msg.images != null) {
      for (final imageData in msg.images!) {
        parts.add(_imageInlineData(imageData));
      }
    }

    if (msg.content != null && msg.content!.isNotEmpty) {
      parts.add({'text': msg.content!});
    }

    return {
      'role': 'user',
      'parts': parts.isEmpty
          ? [
              {'text': ''},
            ]
          : parts,
    };
  }

  static Map<String, dynamic> _convertAssistantMessage(LLMMessage msg) {
    final parts = <Map<String, dynamic>>[];

    if (msg.content != null && msg.content!.isNotEmpty) {
      parts.add({'text': msg.content!});
    }

    if (msg.toolCalls != null) {
      for (final tc in msg.toolCalls!) {
        final name = tc['function']?['name'] as String? ?? '';
        final argsRaw = tc['function']?['arguments'];
        final Map<String, dynamic> args;
        if (argsRaw is String) {
          try {
            args = json.decode(argsRaw) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
        } else if (argsRaw is Map<String, dynamic>) {
          args = argsRaw;
        } else {
          args = {};
        }
        parts.add({
          'functionCall': {'name': name, 'args': args},
        });
      }
    }

    return {
      'role': 'model',
      'parts': parts.isEmpty
          ? [
              {'text': ''},
            ]
          : parts,
    };
  }

  static Map<String, dynamic> _convertToolResultMessage(LLMMessage msg) {
    // Determine the function name — Gemini requires it in functionResponse
    // We try to parse it from content or fall back to empty string
    final name = msg.status ?? '';
    final response = <String, dynamic>{};
    if (msg.content != null) {
      try {
        final decoded = json.decode(msg.content!) as Map<String, dynamic>;
        response.addAll(decoded);
      } catch (_) {
        response['result'] = msg.content;
      }
    }

    return {
      'role': 'user',
      'parts': [
        {
          'functionResponse': {'name': name, 'response': response},
        },
      ],
    };
  }

  static bool _isFunctionResponseContent(Map<String, dynamic> content) {
    if (content['role'] != 'user') return false;
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return false;
    return (parts.first as Map<String, dynamic>).containsKey(
      'functionResponse',
    );
  }

  static Map<String, dynamic> _imageInlineData(String imageData) {
    String mimeType = 'image/jpeg';
    String data = imageData;

    if (imageData.startsWith('data:')) {
      final commaIdx = imageData.indexOf(',');
      if (commaIdx != -1) {
        final header = imageData.substring(5, commaIdx);
        final semicolonIdx = header.indexOf(';');
        if (semicolonIdx != -1) {
          mimeType = header.substring(0, semicolonIdx);
        }
        data = imageData.substring(commaIdx + 1);
      }
    } else if (imageData.startsWith('/9j/')) {
      mimeType = 'image/jpeg';
    } else if (imageData.startsWith('iVBORw0KGgo')) {
      mimeType = 'image/png';
    } else if (imageData.startsWith('R0lGOD')) {
      mimeType = 'image/gif';
    } else if (imageData.startsWith('UklGR')) {
      mimeType = 'image/webp';
    }

    return {
      'inlineData': {'mimeType': mimeType, 'data': data},
    };
  }

  /// Converts an [LLMTool] to Gemini's functionDeclaration format.
  static Map<String, dynamic> toolToFunctionDeclaration(LLMTool tool) {
    final openAiFormat = tool.toJson;
    final function = openAiFormat['function'] as Map<String, dynamic>? ?? {};
    final parameters = function['parameters'] as Map<String, dynamic>? ?? {};
    return {
      'name': function['name'] ?? tool.name,
      'description': function['description'] ?? tool.description,
      'parameters': parameters,
    };
  }
}
