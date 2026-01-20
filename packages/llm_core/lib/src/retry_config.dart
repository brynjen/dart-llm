import 'dart:math' as math;

/// Configuration for retry behavior when making API requests.
///
/// This class configures how the library should retry failed requests
/// with exponential backoff.
///
/// Example:
/// ```dart
/// final config = RetryConfig(
///   maxAttempts: 3,
///   initialDelay: Duration(seconds: 1),
///   maxDelay: Duration(seconds: 30),
/// );
/// ```
class RetryConfig {
  /// Creates a retry configuration.
  ///
  /// [maxAttempts] - Maximum number of retry attempts (default: 3).
  /// [initialDelay] - Initial delay before first retry (default: 1s).
  /// [maxDelay] - Maximum delay between retries (default: 30s).
  /// [backoffMultiplier] - Multiplier for exponential backoff (default: 2.0).
  /// [retryableStatusCodes] - HTTP status codes that should trigger retry (default: [429, 500, 502, 503, 504]).
  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.retryableStatusCodes = const [429, 500, 502, 503, 504],
  });

  /// Maximum number of retry attempts.
  final int maxAttempts;

  /// Initial delay before first retry.
  final Duration initialDelay;

  /// Maximum delay between retries.
  final Duration maxDelay;

  /// Multiplier for exponential backoff.
  ///
  /// Each retry will wait: initialDelay * (backoffMultiplier ^ attemptNumber)
  final double backoffMultiplier;

  /// HTTP status codes that should trigger a retry.
  ///
  /// Default includes rate limiting (429) and server errors (5xx).
  final List<int> retryableStatusCodes;

  /// Whether retries are enabled.
  bool get enabled => maxAttempts > 0;

  /// Calculate the delay for a specific attempt number.
  ///
  /// [attemptNumber] - The attempt number (0-based, so first retry is 0).
  Duration getDelayForAttempt(int attemptNumber) {
    if (attemptNumber < 0) return initialDelay;

    // For very large attempt numbers, the exponential calculation can overflow.
    // Calculate the maximum attempt number before overflow would occur.
    // If the calculated delay would exceed maxDelay, return maxDelay directly.
    if (initialDelay.inMilliseconds > 0 &&
        maxDelay.inMilliseconds >= initialDelay.inMilliseconds) {
      try {
        final maxAttemptBeforeOverflow =
            (math.log(maxDelay.inMilliseconds / initialDelay.inMilliseconds) /
                    math.log(backoffMultiplier))
                .ceil();
        if (attemptNumber >= maxAttemptBeforeOverflow) {
          return maxDelay;
        }
      } catch (e) {
        // If calculation fails (e.g., log of negative), fall through to normal calculation
      }
    }

    // Exponential backoff: initialDelay * (backoffMultiplier ^ attemptNumber)
    final delayMs =
        (initialDelay.inMilliseconds *
                math.pow(backoffMultiplier, attemptNumber))
            .round();

    // Check for overflow (negative result indicates integer overflow)
    if (delayMs < 0) return maxDelay;

    final delay = Duration(milliseconds: delayMs);

    // Cap at maxDelay
    if (delay > maxDelay) return maxDelay;
    return delay;
  }

  /// Check if a status code should trigger a retry.
  bool shouldRetryForStatusCode(int statusCode) {
    return retryableStatusCodes.contains(statusCode);
  }
}
