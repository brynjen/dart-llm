import 'dart:async';

import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_logger.dart';
import 'package:llm_core/src/retry_config.dart';

/// Utility class for retrying operations with exponential backoff.
class RetryUtil {
  /// Logger used to report retries.
  ///
  /// A silent retry is indistinguishable from a slow server: a request that
  /// wedges for a full timeout and then succeeds on the next attempt shows up
  /// as latency and nothing else. Configure `Logger.root` (see
  /// [DefaultLLMLogger]) to see them.
  static LLMLogger logger = DefaultLLMLogger('llm_core.retry');

  /// Execute a function with retry logic.
  ///
  /// [operation] - The async operation to execute.
  /// [config] - Retry configuration (null means no retries).
  /// [isRetryable] - Optional function to determine if an error is retryable.
  /// [onRetry] - Optional callback invoked before each retry, with the
  ///   zero-based attempt number that just failed, the error, and the delay
  ///   before the next attempt.
  ///
  /// Returns the result of the operation, or throws the last error if all retries fail.
  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    RetryConfig? config,
    bool Function(Object error)? isRetryable,
    void Function(int attempt, Object error, Duration delay)? onRetry,
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
        logger.warning(
          'retrying after attempt ${attempt + 1}/${config.maxAttempts + 1} '
          'failed; waiting ${delay.inMilliseconds}ms',
          error,
        );
        onRetry?.call(attempt, error, delay);
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
