import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// VLLM-specific error handling utilities.
class VLLMErrorHandler extends BackendErrorHandler {
  /// Handles VLLM-specific 400 Bad Request errors.
  ///
  /// VLLM returns specific error messages for unsupported features:
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
      final error = errorData is Map<String, dynamic>
          ? errorData['error']
          : null;
      final errorMessage = switch (error) {
        String() => error,
        Map<String, dynamic>() => error['message'] as String? ?? '',
        _ => '',
      };

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

      // Server-configuration failures. vLLM names the missing CLI flag, but
      // the message reads as a request error, so callers reasonably look at
      // their code instead of how the server was started. Restate it as the
      // configuration problem it is.
      if (errorMessage.contains('--tool-call-parser') ||
          errorMessage.contains('enable-auto-tool-choice')) {
        throw ToolsNotSupportedException(
          model,
          'This vLLM server was started without tool-calling support. '
          'Restart it with --enable-auto-tool-choice and a --tool-call-parser '
          'matching the model\'s output format (for example "hermes" for '
          'Qwen3-family models, "qwen3_xml" for Qwen3-Coder, "llama3_json" for '
          'Llama 3). Original error: $errorMessage',
        );
      }

      if (errorMessage.contains('--reasoning-parser') ||
          errorMessage.contains('reasoning_config')) {
        throw ThinkingNotSupportedException(
          model,
          'thinking_token_budget requires a reasoning parser, and this vLLM '
          'server was started without one. Either restart it with '
          '--reasoning-parser (for example "qwen3" for Qwen3-family models) or '
          'drop the reasoning budget — thinking itself still works, and '
          'llm_vllm splits inline <think> tags when no parser is configured. '
          'Original error: $errorMessage',
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
