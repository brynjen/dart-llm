/// Configuration for request timeouts.
///
/// This class provides standardized timeout configuration across all backends.
///
/// Example:
/// ```dart
/// final config = TimeoutConfig(
///   connectionTimeout: Duration(seconds: 10),
///   readTimeout: Duration(minutes: 2),
///   totalTimeout: Duration(minutes: 10),
/// );
/// ```
class TimeoutConfig {
  /// Creates a timeout configuration.
  ///
  /// [connectionTimeout] - Maximum time to wait for connection (default: 10s).
  /// [readTimeout] - Maximum time to wait for data after connection (default: 2 minutes).
  /// [totalTimeout] - Maximum total time for entire request (default: 10 minutes).
  /// [readTimeoutForLargePayloads] - Read timeout for large payloads > 1MB (default: 5 minutes).
  const TimeoutConfig({
    this.connectionTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(minutes: 2),
    this.totalTimeout = const Duration(minutes: 10),
    this.readTimeoutForLargePayloads = const Duration(minutes: 5),
    this.largePayloadThreshold = 1024 * 1024, // 1MB
  });

  /// Maximum time to wait for connection establishment.
  final Duration connectionTimeout;

  /// Maximum time to wait for data after connection is established.
  final Duration readTimeout;

  /// Maximum total time for entire request (connection + read).
  final Duration totalTimeout;

  /// Read timeout for large payloads (e.g., images).
  final Duration readTimeoutForLargePayloads;

  /// Threshold in bytes for considering a payload "large".
  final int largePayloadThreshold;

  /// Get the appropriate read timeout based on payload size.
  Duration getReadTimeoutForPayload(int payloadSizeBytes) {
    if (payloadSizeBytes > largePayloadThreshold) {
      return readTimeoutForLargePayloads;
    }
    return readTimeout;
  }

  /// Default timeout configuration.
  static const TimeoutConfig defaultConfig = TimeoutConfig();
}
