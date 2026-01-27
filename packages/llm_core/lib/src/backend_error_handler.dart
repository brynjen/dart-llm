import 'dart:convert';

import 'package:llm_core/src/exceptions.dart';

/// Base class for backend-specific error handlers.
///
/// Provides common error handling patterns that can be extended
/// by backend-specific implementations.
abstract class BackendErrorHandler {
  /// Handles a bad request (400) error response.
  ///
  /// [errorBody] - The error response body
  /// [model] - The model identifier
  /// [statusCode] - The HTTP status code
  ///
  /// Throws appropriate exceptions based on the error content.
  static Future<void> handleBadRequest({
    required String errorBody,
    required String model,
    int statusCode = 400,
  }) async {
    try {
      final errorData = json.decode(errorBody);
      final errorMessage = _extractErrorMessage(errorData);

      throw LLMApiException(
        'Bad request: $errorMessage',
        statusCode: statusCode,
        responseBody: errorBody,
      );
    } catch (e) {
      if (e is LLMApiException) {
        rethrow;
      }
      throw LLMApiException(
        'Bad request',
        statusCode: statusCode,
        responseBody: errorBody,
      );
    }
  }

  /// Extracts error message from error data.
  ///
  /// Default implementation looks for 'error' key.
  /// Subclasses can override for different formats.
  static String _extractErrorMessage(dynamic errorData) {
    if (errorData is Map<String, dynamic>) {
      return errorData['error'] as String? ?? '';
    }
    return '';
  }
}
