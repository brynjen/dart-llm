import 'dart:async';

import 'package:llm_core/src/exceptions.dart';
import 'package:http/http.dart' as http;
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
    // A deliberate stop is never retried. This held before only by accident —
    // the message happens to contain none of the substrings matched below —
    // which is not a property to rely on when getting it wrong means re-issuing
    // the very request the caller just cancelled.
    if (error is http.RequestAbortedException) {
      return false;
    }

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

  /// Whether an error that ended a *stream* should be retried by re-issuing
  /// the request.
  ///
  /// [isRetryableError] plus one exclusion: a read timeout. The two differ
  /// because of what they cost when they are wrong. A stream read timeout has
  /// already waited `TimeoutConfig.readTimeout` — 90 seconds by default —
  /// before it fires, so retrying it three more times turns a slow failure
  /// into what a user reads as a hang, and the request that never produced a
  /// byte is unlikely to produce one on the next attempt either. A request
  /// that never got going is a different case and is already retried around
  /// the send, where the wait is short.
  static bool isRetryableStreamError(Object error, RetryConfig? retryConfig) {
    if (error is TimeoutException) return false;
    return isRetryableError(error, retryConfig);
  }
}
