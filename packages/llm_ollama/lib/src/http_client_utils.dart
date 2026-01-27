import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Ollama-specific error handling utilities.
class OllamaErrorHandler extends BackendErrorHandler {
  /// Handles Ollama-specific 400 Bad Request errors.
  ///
  /// Ollama returns specific error messages for unsupported features:
  /// - "does not support thinking" -> ThinkingNotSupportedException
  /// - "does not support tools" -> ToolsNotSupportedException
  /// - "does not support chat" -> Generic LLMApiException
  static Future<void> handleBadRequestError({
    required String errorBody,
    required String model,
    required bool thinkRequested,
    required bool toolsRequested,
  }) async {
    try {
      final errorData = json.decode(errorBody);
      final errorMessage = errorData['error'] as String? ?? '';

      if (thinkRequested &&
          errorMessage.contains('does not support thinking')) {
        throw ThinkingNotSupportedException(
          model,
          'Model $model does not support thinking',
        );
      }

      if (toolsRequested && errorMessage.contains('does not support tools')) {
        throw ToolsNotSupportedException(
          model,
          'Model $model does not support tools',
        );
      }

      if (errorMessage.contains('does not support chat')) {
        throw LLMApiException(
          'Model $model does not support chat - use a chat/completion model instead',
          statusCode: 400,
          responseBody: errorBody,
        );
      }

      throw LLMApiException(
        'Bad request: $errorMessage',
        statusCode: 400,
        responseBody: errorBody,
      );
    } catch (e) {
      if (e is ThinkingNotSupportedException ||
          e is ToolsNotSupportedException ||
          e is LLMApiException) {
        rethrow;
      }
      throw LLMApiException(
        'Bad request',
        statusCode: 400,
        responseBody: errorBody,
      );
    }
  }
}
