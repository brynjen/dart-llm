import 'dart:async';

import 'exceptions.dart';
import 'retry_config.dart';

/// Utility class for retrying operations with exponential backoff.
class RetryUtil {
  /// Execute a function with retry logic.
  ///
  /// [operation] - The async operation to execute.
  /// [config] - Retry configuration (null means no retries).
  /// [isRetryable] - Optional function to determine if an error is retryable.
  ///
  /// Returns the result of the operation, or throws the last error if all retries fail.
  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    RetryConfig? config,
    bool Function(Object error)? isRetryable,
  }) async {
    if (config == null || !config.enabled) {
      return await operation();
    }

    Object? lastError;
    int attempt = 0;

    while (attempt <= config.maxAttempts) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;

        // Check if error is retryable
        if (!_isRetryableError(error, config, isRetryable)) {
          rethrow;
        }

        // Don't retry if this was the last attempt
        if (attempt >= config.maxAttempts) {
          break;
        }

        // Calculate delay and wait
        final delay = config.getDelayForAttempt(attempt);
        await Future.delayed(delay);

        attempt++;
      }
    }

    // All retries exhausted, throw last error
    throw lastError!;
  }

  /// Check if an error is retryable.
  static bool _isRetryableError(
    Object error,
    RetryConfig config,
    bool Function(Object error)? customIsRetryable,
  ) {
    // Use custom function if provided
    if (customIsRetryable != null) {
      return customIsRetryable(error);
    }

    // Check for LLMApiException with retryable status code
    if (error is LLMApiException) {
      if (error.statusCode != null) {
        return config.shouldRetryForStatusCode(error.statusCode!);
      }
    }

    // Check for network-related errors (timeouts, connection errors)
    if (error is TimeoutException) {
      return true;
    }

    // Check for SocketException or other network errors
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('timeout')) {
      return true;
    }

    return false;
  }
}
