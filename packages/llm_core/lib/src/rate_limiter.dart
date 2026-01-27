import 'dart:async';

/// Configuration for rate limiting requests.
///
/// Rate limiting helps prevent hitting API rate limits by controlling
/// the number of requests made per time period.
///
/// Example:
/// ```dart
/// final rateLimiter = RateLimiter(
///   maxRequests: 60,
///   windowDuration: Duration(minutes: 1),
/// );
/// ```
class RateLimiter {
  /// Creates a rate limiter configuration.
  ///
  /// [maxRequests] - Maximum number of requests allowed in the time window.
  /// [windowDuration] - Duration of the time window.
  /// [burstSize] - Maximum burst size (allows short bursts above the rate limit).
  ///   If null, defaults to [maxRequests].
  const RateLimiter({
    required this.maxRequests,
    required this.windowDuration,
    int? burstSize,
  }) : burstSize = burstSize ?? maxRequests;

  /// Create a disabled rate limiter (no rate limiting).
  const RateLimiter.disabled()
    : maxRequests = 0,
      windowDuration = const Duration(seconds: 1),
      burstSize = 0;

  /// Maximum number of requests allowed in the time window.
  final int maxRequests;

  /// Duration of the time window.
  final Duration windowDuration;

  /// Maximum burst size (allows short bursts above the rate limit).
  final int burstSize;

  /// Whether rate limiting is enabled.
  bool get enabled => maxRequests > 0;
}

/// Token bucket rate limiter implementation.
///
/// Uses a token bucket algorithm to enforce rate limits.
/// Tokens are added at a steady rate, and each request consumes a token.
class TokenBucketRateLimiter {
  /// Creates a token bucket rate limiter.
  ///
  /// [config] - Rate limiter configuration.
  TokenBucketRateLimiter(this.config)
    : _tokens = config.burstSize.toDouble(),
      _lastRefill = DateTime.now();

  final RateLimiter config;
  double _tokens;
  DateTime _lastRefill;
  final _queue = <Completer<void>>[];
  Timer? _refillTimer;

  /// Wait for a token to become available.
  ///
  /// This method will block until a token is available or the operation
  /// should proceed based on the rate limit configuration.
  Future<void> acquire() async {
    if (!config.enabled) {
      return;
    }

    _refillTokens();

    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return;
    }

    // Need to wait for tokens
    final completer = Completer<void>();
    _queue.add(completer);

    // Start refill timer if not already running
    if (_refillTimer == null || !_refillTimer!.isActive) {
      _startRefillTimer();
    }

    return completer.future;
  }

  /// Refill tokens based on elapsed time.
  void _refillTokens() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill);

    if (elapsed <= Duration.zero) {
      return;
    }

    // Calculate tokens to add based on elapsed time
    final tokensPerSecond =
        config.maxRequests / config.windowDuration.inSeconds;
    final tokensToAdd = elapsed.inMilliseconds / 1000.0 * tokensPerSecond;

    _tokens = (_tokens + tokensToAdd).clamp(0.0, config.burstSize.toDouble());
    _lastRefill = now;
  }

  /// Start the refill timer to process queued requests.
  void _startRefillTimer() {
    if (_queue.isEmpty) {
      return;
    }

    // Calculate delay until next token is available
    final tokensPerSecond =
        config.maxRequests / config.windowDuration.inSeconds;
    final delayMs = (1.0 / tokensPerSecond * 1000).ceil();

    _refillTimer = Timer(Duration(milliseconds: delayMs), () {
      _refillTokens();

      // Process queued requests
      while (_queue.isNotEmpty && _tokens >= 1.0) {
        _tokens -= 1.0;
        final completer = _queue.removeAt(0);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      // Continue refill timer if there are still queued requests
      if (_queue.isNotEmpty) {
        _startRefillTimer();
      } else {
        _refillTimer = null;
      }
    });
  }

  /// Dispose of the rate limiter and cancel any pending operations.
  void dispose() {
    _refillTimer?.cancel();
    for (final completer in _queue) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Rate limiter disposed'));
      }
    }
    _queue.clear();
  }
}

/// Rate limiter utility for managing request rate limits.
class RateLimiterUtil {
  /// Execute an operation with rate limiting.
  ///
  /// [operation] - The async operation to execute.
  /// [rateLimiter] - Rate limiter instance (null means no rate limiting).
  ///
  /// Returns the result of the operation.
  static Future<T> executeWithRateLimit<T>({
    required Future<T> Function() operation,
    TokenBucketRateLimiter? rateLimiter,
  }) async {
    if (rateLimiter != null) {
      await rateLimiter.acquire();
    }
    return await operation();
  }
}
