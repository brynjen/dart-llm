/// Live statistics for a single VLLM instance within an [VLLMPool].
class VLLMInstanceStats {
  const VLLMInstanceStats({
    required this.baseUrl,
    required this.healthy,
    required this.activeConcurrent,
    required this.maxConcurrent,
    required this.queuedRequests,
  });

  /// The base URL of this instance.
  final String baseUrl;

  /// Whether the instance passed its last health check (or `true` if health
  /// checking is disabled).
  final bool healthy;

  /// Number of requests currently in-flight on this instance.
  final int activeConcurrent;

  /// The configured maximum concurrent requests for this instance.
  final int maxConcurrent;

  /// Number of requests queued waiting for a free slot on this instance.
  final int queuedRequests;

  /// Available capacity (may be negative if load reporting is racing).
  int get availableCapacity => maxConcurrent - activeConcurrent;

  @override
  String toString() =>
      'VLLMInstanceStats($baseUrl: $activeConcurrent/$maxConcurrent active, '
      '$queuedRequests queued, ${healthy ? "healthy" : "unhealthy"})';
}

/// Aggregate live statistics for an [VLLMPool].
class VLLMPoolStats {
  const VLLMPoolStats({required this.instances});

  /// Per-instance statistics.
  final List<VLLMInstanceStats> instances;

  /// Total requests currently in-flight across all instances.
  int get totalActive =>
      instances.fold(0, (sum, i) => sum + i.activeConcurrent);

  /// Total requests queued across all instances.
  int get totalQueued => instances.fold(0, (sum, i) => sum + i.queuedRequests);

  /// Number of currently healthy instances.
  int get healthyInstances => instances.where((i) => i.healthy).length;

  @override
  String toString() =>
      'VLLMPoolStats(${instances.length} instances, '
      '$totalActive active, $totalQueued queued, '
      '$healthyInstances/${instances.length} healthy)';
}
