import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Handles error responses from the Google Gemini API.
class GeminiErrorHandler {
  /// Parses Google API error JSON and throws an appropriate [LLMApiException].
  ///
  /// Google error format:
  /// ```json
  /// {"error": {"code": 400, "message": "...", "status": "INVALID_ARGUMENT"}}
  /// ```
  static Never handleError({
    required int statusCode,
    required String errorBody,
  }) {
    String message = 'Gemini API error';
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
