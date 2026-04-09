/// Configuration for background health polling of Ollama instances.
///
/// When provided to [OllamaPool], the pool polls each instance's
/// `/api/version` endpoint at [interval]. Instances that fail the check
/// are marked unhealthy and excluded from routing until they recover.
///
/// Example:
/// ```dart
/// OllamaPool(
///   instances: [...],
///   healthCheck: HealthCheckConfig(
///     interval: Duration(seconds: 30),
///     timeout: Duration(seconds: 5),
///   ),
/// )
/// ```
class HealthCheckConfig {
  const HealthCheckConfig({
    this.interval = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 5),
  });

  /// How often to poll each instance.
  final Duration interval;

  /// Timeout for each health-check request.
  final Duration timeout;
}

/// Describes a change in health state for one Ollama instance.
class OllamaInstanceStateChange {
  const OllamaInstanceStateChange({
    required this.baseUrl,
    required this.healthy,
  });

  /// The base URL of the affected instance.
  final String baseUrl;

  /// `true` if the instance just became healthy; `false` if it just went down.
  final bool healthy;

  @override
  String toString() =>
      'OllamaInstanceStateChange(baseUrl: $baseUrl, healthy: $healthy)';
}
