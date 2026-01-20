import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_message.dart';

/// Validation utilities for LLM requests.
class Validation {
  /// Maximum message content length (in characters).
  ///
  /// This is a reasonable default, but backends may have different limits.
  static const int maxMessageContentLength = 1000000; // 1M characters

  /// Maximum number of messages in a conversation.
  static const int maxMessages = 10000;

  /// Maximum number of images per message.
  static const int maxImagesPerMessage = 10;

  /// Validate messages for a chat request.
  ///
  /// Throws [LLMApiException] if validation fails.
  static void validateMessages(List<LLMMessage> messages) {
    if (messages.isEmpty) {
      throw const LLMApiException('Messages list cannot be empty', statusCode: 400);
    }

    if (messages.length > maxMessages) {
      throw LLMApiException(
        'Too many messages: ${messages.length} (max: $maxMessages)',
        statusCode: 400,
      );
    }

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      validateMessage(message, index: i);
    }
  }

  /// Validate a single message.
  ///
  /// Throws [LLMApiException] if validation fails.
  static void validateMessage(LLMMessage message, {int? index}) {
    final prefix = index != null ? 'Message $index: ' : '';

    // Check content length
    if (message.content != null) {
      if (message.content!.length > maxMessageContentLength) {
        throw LLMApiException(
          '${prefix}Message content too long: ${message.content!.length} characters (max: $maxMessageContentLength)',
          statusCode: 400,
        );
      }
    }

    // Check images
    if (message.images != null) {
      if (message.images!.length > maxImagesPerMessage) {
        throw LLMApiException(
          '${prefix}Too many images: ${message.images!.length} (max: $maxImagesPerMessage)',
          statusCode: 400,
        );
      }

      // Validate image format (basic check for base64 or URL)
      for (int i = 0; i < message.images!.length; i++) {
        final image = message.images![i];
        if (image.isEmpty) {
          throw LLMApiException('${prefix}Image $i is empty', statusCode: 400);
        }
      }
    }

    // Validate role-specific requirements
    switch (message.role) {
      case LLMRole.user:
        // User messages should have content or images
        if ((message.content == null || message.content!.isEmpty) &&
            (message.images == null || message.images!.isEmpty)) {
          throw LLMApiException(
            '${prefix}User message must have content or images',
            statusCode: 400,
          );
        }
        break;
      case LLMRole.assistant:
        // Assistant messages can have content, tool calls, or both
        // Empty string content is valid if toolCalls exist
        final hasContent =
            message.content != null && message.content!.isNotEmpty;
        final hasToolCalls =
            message.toolCalls != null && message.toolCalls!.isNotEmpty;
        if (!hasContent && !hasToolCalls) {
          throw LLMApiException(
            '${prefix}Assistant message must have content or tool calls',
            statusCode: 400,
          );
        }
        break;
      case LLMRole.tool:
        // Tool messages must have content and toolCallId
        if (message.content == null || message.content!.isEmpty) {
          throw LLMApiException(
            '${prefix}Tool message must have content',
            statusCode: 400,
          );
        }
        if (message.toolCallId == null || message.toolCallId!.isEmpty) {
          throw LLMApiException(
            '${prefix}Tool message must have toolCallId',
            statusCode: 400,
          );
        }
        break;
      case LLMRole.system:
        // System messages should have content
        if (message.content == null || message.content!.isEmpty) {
          throw LLMApiException(
            '${prefix}System message must have content',
            statusCode: 400,
          );
        }
        break;
    }
  }

  /// Validate a model name.
  ///
  /// Throws [LLMApiException] if validation fails.
  static void validateModelName(String model) {
    if (model.isEmpty) {
      throw const LLMApiException('Model name cannot be empty', statusCode: 400);
    }

    if (model.length > 200) {
      throw LLMApiException(
        'Model name too long: ${model.length} characters (max: 200)',
        statusCode: 400,
      );
    }
  }

  /// Validate tool parameters.
  ///
  /// Throws [LLMApiException] if validation fails.
  static void validateToolArguments(
    Map<String, dynamic> arguments,
    String toolName,
  ) {
    if (arguments.isEmpty) {
      // Empty arguments are allowed
      return;
    }

    // Check for reasonable argument count
    if (arguments.length > 100) {
      throw LLMApiException(
        'Tool $toolName has too many arguments: ${arguments.length} (max: 100)',
        statusCode: 400,
      );
    }

    // Validate argument values are serializable
    for (final entry in arguments.entries) {
      final value = entry.value;
      if (value != null &&
          value is! String &&
          value is! int &&
          value is! double &&
          value is! bool &&
          value is! List &&
          value is! Map) {
        throw LLMApiException(
          'Tool $toolName argument "${entry.key}" has invalid type: ${value.runtimeType}',
          statusCode: 400,
        );
      }
    }
  }
}
