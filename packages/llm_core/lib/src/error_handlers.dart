import 'dart:async';

import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/retry_config.dart';

/// Utility functions for error handling in HTTP-based repositories.
class ErrorHandlers {
  /// Determines if an error is retryable based on common patterns.
  ///
  /// [error] - The error to check
  /// [retryConfig] - Optional retry configuration for status code checking
  ///
  /// Returns true if the error should be retried.
  static bool isRetryableError(Object error, RetryConfig? retryConfig) {
    if (error is LLMApiException && error.statusCode != null) {
      return retryConfig?.shouldRetryForStatusCode(error.statusCode!) ?? false;
    }

    if (error is TimeoutException) {
      return true;
    }

    final errorString = error.toString().toLowerCase();
    return errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('timeout');
  }
}
