import 'package:http/http.dart' as http;
import 'package:llm_core/src/rate_limiter.dart';
import 'package:llm_core/src/response_cache.dart';
import 'package:llm_core/src/retry_config.dart';
import 'package:llm_core/src/timeout_config.dart';

/// Base class for chat repository builders.
///
/// Provides common builder functionality shared across all backend implementations.
/// Subclasses should extend this and add backend-specific configuration methods.
abstract class ChatRepositoryBuilderBase<T> {
  /// Creates a base builder with common configuration options.
  ChatRepositoryBuilderBase();

  int? _maxToolAttempts;
  RetryConfig? _retryConfig;
  TimeoutConfig? _timeoutConfig;
  RateLimiter? _rateLimiter;
  ResponseCache? _responseCache;
  http.Client? _httpClient;

  /// Set the maximum number of tool attempts.
  T maxToolAttempts(int maxToolAttempts) {
    _maxToolAttempts = maxToolAttempts;
    return this as T;
  }

  /// Set the retry configuration.
  T retryConfig(RetryConfig retryConfig) {
    _retryConfig = retryConfig;
    return this as T;
  }

  /// Set the timeout configuration.
  T timeoutConfig(TimeoutConfig timeoutConfig) {
    _timeoutConfig = timeoutConfig;
    return this as T;
  }

  /// Set the rate limiter configuration.
  T rateLimiter(RateLimiter rateLimiter) {
    _rateLimiter = rateLimiter;
    return this as T;
  }

  /// Set the response cache.
  T responseCache(ResponseCache responseCache) {
    _responseCache = responseCache;
    return this as T;
  }

  /// Set a custom HTTP client.
  T httpClient(http.Client httpClient) {
    _httpClient = httpClient;
    return this as T;
  }

  /// Get the maximum tool attempts (with default).
  int get maxToolAttemptsValue => _maxToolAttempts ?? 25;

  /// Get the retry configuration.
  RetryConfig? get retryConfigValue => _retryConfig;

  /// Get the timeout configuration.
  TimeoutConfig? get timeoutConfigValue => _timeoutConfig;

  /// Get the rate limiter configuration.
  RateLimiter? get rateLimiterValue => _rateLimiter;

  /// Get the response cache.
  ResponseCache? get responseCacheValue => _responseCache;

  /// Get the HTTP client.
  http.Client? get httpClientValue => _httpClient;

  /// Build the repository instance.
  /// Subclasses must implement this method.
  dynamic build();
}
