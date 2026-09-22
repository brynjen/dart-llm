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

  /// Re-runs [build] when it fails **before emitting anything**.
  ///
  /// [executeWithRetry] covers a request that fails while it is being sent. It
  /// cannot cover one that fails afterwards, because by then it has already
  /// returned the response and the stream is being consumed — and providers
  /// routinely report a failure that way. A streaming endpoint answers `200`,
  /// opens the stream and then delivers the error in-band, as an `error`
  /// event:
  ///
  /// ```
  /// data: {"error":{"message":"gemini-3.5-flash-lite is currently
  ///        experiencing high demand","code":"service_unavailable"}}
  /// ```
  ///
  /// That is the same `503` the HTTP layer would have retried three times,
  /// and without this it was not retried at all — the turn simply failed.
  ///
  /// **Only while nothing has been emitted.** Once an event has reached the
  /// caller, re-running would deliver the turn's opening twice, so an error
  /// after that point is rethrown untouched however retryable it looks. In
  /// practice this covers exactly the window a caller cannot see: the model
  /// has produced no tokens yet, so a retry is indistinguishable from the
  /// request having taken longer.
  ///
  /// [isRetryable] decides which errors qualify. Backends pass a predicate
  /// that also requires the send to have already succeeded, so the attempts
  /// here do not multiply with [executeWithRetry]'s: each error is retried by
  /// one of the two, never both.
  static Stream<T> retryingStream<T>({
    required Stream<T> Function() build,
    RetryConfig? config,
    bool Function(Object error)? isRetryable,
  }) async* {
    if (config == null || !config.enabled) {
      yield* build();
      return;
    }

    var attempt = 0;
    while (true) {
      var emitted = false;
      try {
        await for (final event in build()) {
          emitted = true;
          yield event;
        }
        return;
      } catch (error, stackTrace) {
        if (emitted ||
            attempt >= config.maxAttempts ||
            !_isRetryableError(error, config, isRetryable)) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        final delay = config.getDelayForAttempt(attempt);
        logger.warning(
          'retrying stream after attempt ${attempt + 1}/'
          '${config.maxAttempts + 1} failed before emitting anything; '
          'waiting ${delay.inMilliseconds}ms',
          error,
        );
        await Future.delayed(delay);
        attempt++;
      }
    }
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
