import 'dart:convert';

import 'package:llm_core/src/tool/llm_tool_call.dart';

/// A typed content part inside an [LLMMessage].
sealed class LLMMessageContent {
  /// Creates a message content part.
  const LLMMessageContent();

  /// Converts this part to OpenAI-compatible content JSON.
  Map<String, dynamic> toJson();
}

/// Text content inside an [LLMMessage].
final class LLMTextContent extends LLMMessageContent {
  /// Creates text content.
  const LLMTextContent(this.text);

  /// The text payload.
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LLMTextContent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Image content inside an [LLMMessage].
final class LLMImageContent extends LLMMessageContent {
  /// Creates image content from a URL, data URI, or base64 payload.
  const LLMImageContent(this.data, {this.mimeType = 'image/png'});

  /// URL, data URI, or base64 payload.
  final String data;

  /// MIME type used when [data] is a raw base64 payload.
  final String mimeType;

  /// Returns an OpenAI-compatible image URL string.
  String get imageUrl {
    if (data.startsWith('http://') ||
        data.startsWith('https://') ||
        data.startsWith('data:')) {
      return data;
    }
    return 'data:$mimeType;base64,$data';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image_url',
    'image_url': {'url': imageUrl},
  };

  @override
  String toString() => imageUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LLMImageContent &&
          other.data == data &&
          other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(data, mimeType);
}

/// Represents a message in an LLM conversation.
class LLMMessage {
  LLMMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.images,
    List<dynamic>? toolCalls,
    List<LLMMessageContent>? contentParts,
    this.status,
  }) : toolCalls = _normalizeToolCalls(toolCalls),
       contentParts = contentParts ?? _contentPartsFromCompat(content, images);

  /// The text content of the message.
  final String? content;

  /// The role of the message sender.
  final LLMRole role;

  /// ID for tool call responses (used by some providers like ChatGPT).
  final String? toolCallId;

  /// Base64 encoded images or URLs for vision-capable models.
  final List<String>? images;

  /// Typed content parts for text, image, and future multimodal payloads.
  final List<LLMMessageContent> contentParts;

  /// Typed tool calls made by the assistant.
  final List<LLMToolCall>? toolCalls;

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
        json['content'] = contentParts
            .map((part) => part.toJson())
            .toList(growable: false);
        break;
      default:
        json['content'] = content;
        break;
    }
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!
          .map((toolCall) => toolCall.toApiFormat())
          .toList(growable: false);
    }
    return json;
  }

  static List<LLMMessageContent> _contentPartsFromCompat(
    String? content,
    List<String>? images,
  ) {
    final parts = <LLMMessageContent>[];
    if (content != null) parts.add(LLMTextContent(content));
    for (final image in images ?? const <String>[]) {
      parts.add(LLMImageContent(image));
    }
    return parts;
  }

  static List<LLMToolCall>? _normalizeToolCalls(List<dynamic>? toolCalls) {
    if (toolCalls == null) return null;
    return toolCalls
        .map((toolCall) => LLMToolCall.from(toolCall as Object))
        .toList(growable: false);
  }

  @override
  String toString() => jsonEncode(toJson());
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
