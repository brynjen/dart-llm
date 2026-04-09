import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Handles error responses from the Anthropic API.
class ClaudeErrorHandler {
  /// Parses Anthropic error JSON and throws an appropriate [LLMApiException].
  ///
  /// Anthropic error format:
  /// ```json
  /// {"type": "error", "error": {"type": "invalid_request_error", "message": "..."}}
  /// ```
  static Never handleError({
    required int statusCode,
    required String errorBody,
  }) {
    String message = 'Anthropic API error';
    try {
      final decoded = json.decode(errorBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      if (error != null) {
        message = error['message'] as String? ?? message;
      }
    } catch (_) {
      if (errorBody.isNotEmpty) message = errorBody;
    }
    throw LLMApiException(
      message,
      statusCode: statusCode,
      responseBody: errorBody,
    );
  }
}
