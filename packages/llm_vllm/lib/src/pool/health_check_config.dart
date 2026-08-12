/// Configuration for background health polling of VLLM instances.
///
/// When provided to [VLLMPool], the pool polls each instance's
/// `/v1/models` endpoint at [interval]. Instances that fail the check
/// are marked unhealthy and excluded from routing until they recover.
///
/// Example:
/// ```dart
/// VLLMPool(
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

/// Describes a change in health state for one VLLM instance.
class VLLMInstanceStateChange {
  const VLLMInstanceStateChange({required this.baseUrl, required this.healthy});

  /// The base URL of the affected instance.
  final String baseUrl;

  /// `true` if the instance just became healthy; `false` if it just went down.
  final bool healthy;

  @override
  String toString() =>
      'VLLMInstanceStateChange(baseUrl: $baseUrl, healthy: $healthy)';
}
