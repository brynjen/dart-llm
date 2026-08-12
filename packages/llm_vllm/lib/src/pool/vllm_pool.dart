import 'dart:async';

import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/vllm_base_url.dart';
import 'package:llm_vllm/src/vllm_chat_repository.dart';
import 'package:llm_vllm/src/pool/health_check_config.dart';
import 'package:llm_vllm/src/pool/vllm_instance_config.dart';
import 'package:llm_vllm/src/pool/vllm_model_config.dart';
import 'package:llm_vllm/src/pool/vllm_pool_builder.dart';
import 'package:llm_vllm/src/pool/pool_stats.dart';
import 'package:llm_vllm/src/pool/semaphore.dart';

/// Thrown when no healthy instance accepts the requested model.
class VLLMNoEligibleInstanceException implements Exception {
  const VLLMNoEligibleInstanceException(this.message);
  final String message;
  @override
  String toString() => 'VLLMNoEligibleInstanceException: $message';
}

/// Thrown when [VLLMPool.maxQueueDepth] is reached.
class VLLMQueueFullException implements Exception {
  const VLLMQueueFullException(this.message);
  final String message;
  @override
  String toString() => 'VLLMQueueFullException: $message';
}

// ---------------------------------------------------------------------------
// Internal: per-instance slot
// ---------------------------------------------------------------------------

class _VLLMSlot {
  _VLLMSlot(this.config)
    : _semaphore = Semaphore(config.maxConcurrent),
      repository = VLLMChatRepository(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        maxToolAttempts: config.maxToolAttempts,
        retryConfig: config.retryConfig,
        timeoutConfig: config.timeoutConfig,
      );

  final VLLMInstanceConfig config;
  final VLLMChatRepository repository;
  final Semaphore _semaphore;
  int _activeCount = 0;
  bool healthy = true;

  int get activeCount => _activeCount;
  int get waiting => _semaphore.waiting;

  Future<T> run<T>(Future<T> Function() fn, {Duration? timeout}) async {
    if (timeout != null) {
      await _semaphore.acquireWithTimeout(timeout);
    } else {
      await _semaphore.acquire();
    }
    _activeCount++;
    try {
      return await fn();
    } finally {
      _activeCount--;
      _semaphore.release();
    }
  }

  Stream<T> runStream<T>(Stream<T> Function() fn, {Duration? timeout}) async* {
    if (timeout != null) {
      await _semaphore.acquireWithTimeout(timeout);
    } else {
      await _semaphore.acquire();
    }
    _activeCount++;
    try {
      yield* fn();
    } finally {
      _activeCount--;
      _semaphore.release();
    }
  }

  VLLMInstanceStats get stats => VLLMInstanceStats(
    baseUrl: config.baseUrl,
    healthy: healthy,
    activeConcurrent: _activeCount,
    maxConcurrent: config.maxConcurrent,
    queuedRequests: _semaphore.waiting,
  );
}

// ---------------------------------------------------------------------------
// Internal: routing logic
// ---------------------------------------------------------------------------

class _VLLMRouter {
  /// Selects the best slot for a chat request.
  ///
  /// Priority:
  /// 1. Hard affinity (exclusiveModels) filters out ineligible slots.
  /// 2. Soft affinity (preferredModels) is tried first.
  /// 3. Least-loaded (fewest active requests) wins ties.
  static _VLLMSlot? selectForChat(List<_VLLMSlot> slots, String model) {
    return _select(slots, model);
  }

  /// Selects the best slot for an embedding request.
  ///
  /// Prefers instances flagged with [VLLMInstanceConfig.preferEmbedding]
  /// before falling back to the general least-loaded selection.
  static _VLLMSlot? selectForEmbed(List<_VLLMSlot> slots, String model) {
    final eligible = _eligible(slots, model);
    if (eligible.isEmpty) return null;

    // First: try embedding-preferred instances
    final embedPref = eligible.where((s) => s.config.preferEmbedding).toList();
    if (embedPref.isNotEmpty) return _leastLoaded(embedPref);

    // Second: soft model affinity
    final modelPref = eligible
        .where((s) => s.config.prefersModel(model))
        .toList();
    if (modelPref.isNotEmpty) return _leastLoaded(modelPref);

    return _leastLoaded(eligible);
  }

  static _VLLMSlot? _select(List<_VLLMSlot> slots, String model) {
    final eligible = _eligible(slots, model);
    if (eligible.isEmpty) return null;

    // Soft affinity
    final preferred = eligible
        .where((s) => s.config.prefersModel(model))
        .toList();
    return _leastLoaded(preferred.isNotEmpty ? preferred : eligible);
  }

  static List<_VLLMSlot> _eligible(List<_VLLMSlot> slots, String model) =>
      slots.where((s) => s.healthy && s.config.acceptsModel(model)).toList();

  static _VLLMSlot _leastLoaded(List<_VLLMSlot> candidates) {
    assert(candidates.isNotEmpty);
    _VLLMSlot best = candidates.first;
    for (final slot in candidates.skip(1)) {
      if (slot.activeCount < best.activeCount) best = slot;
    }
    return best;
  }
}

// ---------------------------------------------------------------------------
// Public: VLLMPool
// ---------------------------------------------------------------------------

/// A pool of VLLM instances that acts as a drop-in replacement for
/// [VLLMChatRepository].
///
/// `VLLMPool` distributes requests across multiple VLLM servers with:
/// - **Per-instance concurrency limits** ([VLLMInstanceConfig.maxConcurrent])
/// - **Per-model concurrency limits** ([VLLMModelConfig.maxConcurrent])
/// - **Hard and soft model affinity** for routing to specific GPUs
/// - **Backpressure queuing** — requests queue when all slots are full
/// - **Health checking** — unhealthy instances are excluded from routing
///
/// Example:
/// ```dart
/// final pool = VLLMPool(
///   instances: [
///     VLLMInstanceConfig(
///       baseUrl: 'http://gpu1:8000',
///       maxConcurrent: 3,
///       preferredModels: ['qwen3:4b', 'llama3.2:3b'],
///       preferEmbedding: true,
///     ),
///     VLLMInstanceConfig(
///       baseUrl: 'http://gpu2:8000',
///       maxConcurrent: 1,
///       exclusiveModels: ['llama3.3:70b'],
///     ),
///   ],
///   modelConfigs: [
///     VLLMModelConfig(
///       pattern: 'llama3.3:70b',
///       maxConcurrent: 1,
///       exclusive: true,
///     ),
///   ],
///   healthCheck: HealthCheckConfig(),
/// );
///
/// // Drop-in replacement — same API as VLLMChatRepository:
/// final stream = pool.streamChat('qwen3:4b', messages: [...]);
/// ```
class VLLMPool extends LLMChatRepository {
  VLLMPool({
    required List<VLLMInstanceConfig> instances,
    this.modelConfigs = const [],
    HealthCheckConfig? healthCheck,
    this.queueTimeout,
    this.maxQueueDepth,
  }) : _slots = instances.map(_VLLMSlot.new).toList() {
    assert(instances.isNotEmpty, 'VLLMPool requires at least one instance');
    if (healthCheck != null) _startHealthChecks(healthCheck);
  }

  /// Creates a fluent builder for configuring an [VLLMPool].
  static VLLMPoolBuilder builder() => VLLMPoolBuilder();

  /// Per-model constraints applied across all instances.
  final List<VLLMModelConfig> modelConfigs;

  /// Optional timeout for requests waiting in the queue.
  ///
  /// When set, a request that waits longer than this throws
  /// [VLLMQueueTimeoutException]. Defaults to `null` (wait indefinitely).
  final Duration? queueTimeout;

  /// Optional maximum total queue depth across all instances.
  ///
  /// When set, requests that arrive when this many are already queued throw
  /// [VLLMQueueFullException] immediately without joining the queue.
  /// Defaults to `null` (unbounded).
  final int? maxQueueDepth;

  final List<_VLLMSlot> _slots;

  // Model-level semaphores keyed by VLLMModelConfig.pattern
  final _modelSemaphores = <String, Semaphore>{};

  // Health check timer
  Timer? _healthTimer;

  // State-change stream
  final _stateController =
      StreamController<VLLMInstanceStateChange>.broadcast();

  /// Emits an event whenever an instance transitions between healthy and
  /// unhealthy states. Only active when a [HealthCheckConfig] was provided.
  Stream<VLLMInstanceStateChange> get onInstanceStateChange =>
      _stateController.stream;

  /// Cancels health-check polling, closes internal streams, and releases the
  /// HTTP client held by every pooled instance.
  ///
  /// Call this when the pool is no longer needed. Without it the per-instance
  /// repositories — and their sockets — stay open for the life of the process.
  void dispose() {
    _healthTimer?.cancel();
    for (final slot in _slots) {
      slot.repository.close();
    }
    _stateController.close();
  }

  // -------------------------------------------------------------------------
  // LLMChatRepository implementation
  // -------------------------------------------------------------------------

  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  }) async* {
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    final slot = _VLLMRouter.selectForChat(_slots, model);
    if (slot == null) {
      throw VLLMNoEligibleInstanceException(
        'No healthy instance accepts model "$model". '
        'Check exclusiveModels configuration and instance health.',
      );
    }

    _guardQueueDepth(slot);

    final modelSemaphore = _getOrCreateModelSemaphore(model);
    if (modelSemaphore != null) {
      if (queueTimeout != null) {
        await modelSemaphore.acquireWithTimeout(queueTimeout!);
      } else {
        await modelSemaphore.acquire();
      }
    }

    try {
      yield* slot.runStream(
        () => slot.repository.streamChat(
          model,
          messages: messages,
          think: think,
          tools: tools,
          extra: extra,
          options: options,
        ),
        timeout: queueTimeout,
      );
    } finally {
      modelSemaphore?.release();
    }
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final slot = _VLLMRouter.selectForEmbed(_slots, model);
    if (slot == null) {
      throw VLLMNoEligibleInstanceException(
        'No healthy instance accepts model "$model" for embeddings.',
      );
    }

    _guardQueueDepth(slot);

    final modelSemaphore = _getOrCreateModelSemaphore(model);
    if (modelSemaphore != null) {
      if (queueTimeout != null) {
        await modelSemaphore.acquireWithTimeout(queueTimeout!);
      } else {
        await modelSemaphore.acquire();
      }
    }

    try {
      return await slot.run(
        () => slot.repository.embed(
          model: model,
          messages: messages,
          options: options,
        ),
        timeout: queueTimeout,
      );
    } finally {
      modelSemaphore?.release();
    }
  }

  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) => embed(model: model, messages: messages, options: options);

  // -------------------------------------------------------------------------
  // Observability
  // -------------------------------------------------------------------------

  /// Returns a snapshot of current load across all instances.
  VLLMPoolStats stats() => VLLMPoolStats(
    instances: _slots.map((s) => s.stats).toList(growable: false),
  );

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  VLLMModelConfig? _configFor(String model) {
    for (final c in modelConfigs) {
      if (c.matches(model)) return c;
    }
    return null;
  }

  Semaphore? _getOrCreateModelSemaphore(String model) {
    final config = _configFor(model);
    if (config == null) return null;

    // exclusive: true forces a global limit of 1 for this model
    final limit = config.exclusive ? 1 : config.maxConcurrent;
    if (limit == null) return null;

    return _modelSemaphores.putIfAbsent(config.pattern, () => Semaphore(limit));
  }

  void _guardQueueDepth(_VLLMSlot slot) {
    if (maxQueueDepth == null) return;
    final totalWaiting = _slots.fold(0, (s, sl) => s + sl.waiting);
    if (totalWaiting >= maxQueueDepth!) {
      throw VLLMQueueFullException(
        'Pool queue is full ($totalWaiting/$maxQueueDepth requests queued). '
        'Consider increasing maxQueueDepth or adding more instances.',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Health checking
  // -------------------------------------------------------------------------

  void _startHealthChecks(HealthCheckConfig config) {
    // Run an initial check immediately, then periodically
    _runHealthChecks(config.timeout);
    _healthTimer = Timer.periodic(
      config.interval,
      (_) => _runHealthChecks(config.timeout),
    );
  }

  Future<void> _runHealthChecks(Duration timeout) async {
    for (final slot in _slots) {
      final wasHealthy = slot.healthy;
      bool nowHealthy;
      try {
        // Reuse the slot's own client rather than creating and tearing down a
        // fresh one per instance per tick — that churned a connection pool on
        // every health interval.
        final response = await slot.repository.httpClient
            .get(
              vllmEndpoint(slot.config.baseUrl, 'models'),
              headers: {
                'accept': 'application/json',
                if (slot.config.apiKey != null &&
                    slot.config.apiKey!.isNotEmpty)
                  'authorization': 'Bearer ${slot.config.apiKey}',
              },
            )
            .timeout(timeout);
        nowHealthy = response.statusCode == 200;
      } catch (_) {
        nowHealthy = false;
      }

      slot.healthy = nowHealthy;
      if (wasHealthy != nowHealthy && !_stateController.isClosed) {
        _stateController.add(
          VLLMInstanceStateChange(
            baseUrl: slot.config.baseUrl,
            healthy: nowHealthy,
          ),
        );
      }
    }
  }
}
