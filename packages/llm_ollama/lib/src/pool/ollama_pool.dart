import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/ollama_chat_repository.dart';
import 'package:llm_ollama/src/pool/health_check_config.dart';
import 'package:llm_ollama/src/pool/ollama_instance_config.dart';
import 'package:llm_ollama/src/pool/ollama_model_config.dart';
import 'package:llm_ollama/src/pool/ollama_pool_builder.dart';
import 'package:llm_ollama/src/pool/pool_stats.dart';
import 'package:llm_ollama/src/pool/semaphore.dart';

/// Thrown when no healthy instance accepts the requested model.
class OllamaNoEligibleInstanceException implements Exception {
  const OllamaNoEligibleInstanceException(this.message);
  final String message;
  @override
  String toString() => 'OllamaNoEligibleInstanceException: $message';
}

/// Thrown when [OllamaPool.maxQueueDepth] is reached.
class OllamaQueueFullException implements Exception {
  const OllamaQueueFullException(this.message);
  final String message;
  @override
  String toString() => 'OllamaQueueFullException: $message';
}

// ---------------------------------------------------------------------------
// Internal: per-instance slot
// ---------------------------------------------------------------------------

class _OllamaSlot {
  _OllamaSlot(this.config)
    : _semaphore = Semaphore(config.maxConcurrent),
      repository = OllamaChatRepository(
        baseUrl: config.baseUrl,
        maxToolAttempts: config.maxToolAttempts,
        retryConfig: config.retryConfig,
        timeoutConfig: config.timeoutConfig,
      );

  final OllamaInstanceConfig config;
  final OllamaChatRepository repository;
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

  OllamaInstanceStats get stats => OllamaInstanceStats(
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

class _OllamaRouter {
  /// Selects the best slot for a chat request.
  ///
  /// Priority:
  /// 1. Hard affinity (exclusiveModels) filters out ineligible slots.
  /// 2. Soft affinity (preferredModels) is tried first.
  /// 3. Least-loaded (fewest active requests) wins ties.
  static _OllamaSlot? selectForChat(List<_OllamaSlot> slots, String model) {
    return _select(slots, model, forEmbedding: false);
  }

  /// Selects the best slot for an embedding request.
  ///
  /// Prefers instances flagged with [OllamaInstanceConfig.preferEmbedding]
  /// before falling back to the general least-loaded selection.
  static _OllamaSlot? selectForEmbed(List<_OllamaSlot> slots, String model) {
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

  static _OllamaSlot? _select(
    List<_OllamaSlot> slots,
    String model, {
    required bool forEmbedding,
  }) {
    final eligible = _eligible(slots, model);
    if (eligible.isEmpty) return null;

    // Soft affinity
    final preferred = eligible
        .where((s) => s.config.prefersModel(model))
        .toList();
    return _leastLoaded(preferred.isNotEmpty ? preferred : eligible);
  }

  static List<_OllamaSlot> _eligible(List<_OllamaSlot> slots, String model) =>
      slots.where((s) => s.healthy && s.config.acceptsModel(model)).toList();

  static _OllamaSlot _leastLoaded(List<_OllamaSlot> candidates) {
    assert(candidates.isNotEmpty);
    _OllamaSlot best = candidates.first;
    for (final slot in candidates.skip(1)) {
      if (slot.activeCount < best.activeCount) best = slot;
    }
    return best;
  }
}

// ---------------------------------------------------------------------------
// Public: OllamaPool
// ---------------------------------------------------------------------------

/// A pool of Ollama instances that acts as a drop-in replacement for
/// [OllamaChatRepository].
///
/// `OllamaPool` distributes requests across multiple Ollama servers with:
/// - **Per-instance concurrency limits** ([OllamaInstanceConfig.maxConcurrent])
/// - **Per-model concurrency limits** ([OllamaModelConfig.maxConcurrent])
/// - **Hard and soft model affinity** for routing to specific GPUs
/// - **Embedding isolation** via `keep_alive: '0'` injection
/// - **Backpressure queuing** — requests queue when all slots are full
/// - **Health checking** — unhealthy instances are excluded from routing
///
/// Example:
/// ```dart
/// final pool = OllamaPool(
///   instances: [
///     OllamaInstanceConfig(
///       baseUrl: 'http://gpu1:11434',
///       maxConcurrent: 3,
///       preferredModels: ['qwen3:4b', 'llama3.2:3b'],
///       preferEmbedding: true,
///     ),
///     OllamaInstanceConfig(
///       baseUrl: 'http://gpu2:11434',
///       maxConcurrent: 1,
///       exclusiveModels: ['llama3.3:70b'],
///     ),
///   ],
///   modelConfigs: [
///     OllamaModelConfig(
///       pattern: 'llama3.3:70b',
///       maxConcurrent: 1,
///       exclusive: true,
///       keepAlive: Duration.zero,
///     ),
///   ],
///   healthCheck: HealthCheckConfig(),
/// );
///
/// // Drop-in replacement — same API as OllamaChatRepository:
/// final stream = pool.streamChat('qwen3:4b', messages: [...]);
/// ```
class OllamaPool extends LLMChatRepository {
  OllamaPool({
    required List<OllamaInstanceConfig> instances,
    this.modelConfigs = const [],
    HealthCheckConfig? healthCheck,
    this.queueTimeout,
    this.maxQueueDepth,
  }) : _slots = instances.map(_OllamaSlot.new).toList() {
    assert(instances.isNotEmpty, 'OllamaPool requires at least one instance');
    if (healthCheck != null) _startHealthChecks(healthCheck);
  }

  /// Creates a fluent builder for configuring an [OllamaPool].
  static OllamaPoolBuilder builder() => OllamaPoolBuilder();

  /// Per-model constraints applied across all instances.
  final List<OllamaModelConfig> modelConfigs;

  /// Optional timeout for requests waiting in the queue.
  ///
  /// When set, a request that waits longer than this throws
  /// [OllamaQueueTimeoutException]. Defaults to `null` (wait indefinitely).
  final Duration? queueTimeout;

  /// Optional maximum total queue depth across all instances.
  ///
  /// When set, requests that arrive when this many are already queued throw
  /// [OllamaQueueFullException] immediately without joining the queue.
  /// Defaults to `null` (unbounded).
  final int? maxQueueDepth;

  final List<_OllamaSlot> _slots;

  // Model-level semaphores keyed by OllamaModelConfig.pattern
  final _modelSemaphores = <String, Semaphore>{};

  // Health check timer
  Timer? _healthTimer;

  // State-change stream
  final _stateController =
      StreamController<OllamaInstanceStateChange>.broadcast();

  /// Emits an event whenever an instance transitions between healthy and
  /// unhealthy states. Only active when a [HealthCheckConfig] was provided.
  Stream<OllamaInstanceStateChange> get onInstanceStateChange =>
      _stateController.stream;

  /// Cancels health-check polling and closes internal streams.
  ///
  /// Call this when the pool is no longer needed to avoid timer leaks.
  void dispose() {
    _healthTimer?.cancel();
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
    StreamChatOptions? options,
  }) async* {
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    final slot = _OllamaRouter.selectForChat(_slots, model);
    if (slot == null) {
      throw OllamaNoEligibleInstanceException(
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
      final mergedOptions = _injectModelKeepAlive(model, options);
      yield* slot.runStream(
        () => slot.repository.streamChat(
          model,
          messages: messages,
          think: think,
          tools: tools,
          extra: extra,
          options: mergedOptions,
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
    final slot = _OllamaRouter.selectForEmbed(_slots, model);
    if (slot == null) {
      throw OllamaNoEligibleInstanceException(
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
      final embedOptions = _injectEmbeddingKeepAlive(model, slot, options);
      return await slot.run(
        () => slot.repository.embed(
          model: model,
          messages: messages,
          options: embedOptions,
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
  OllamaPoolStats stats() => OllamaPoolStats(
    instances: _slots.map((s) => s.stats).toList(growable: false),
  );

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  OllamaModelConfig? _configFor(String model) {
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

  void _guardQueueDepth(_OllamaSlot slot) {
    if (maxQueueDepth == null) return;
    final totalWaiting = _slots.fold(0, (s, sl) => s + sl.waiting);
    if (totalWaiting >= maxQueueDepth!) {
      throw OllamaQueueFullException(
        'Pool queue is full ($totalWaiting/$maxQueueDepth requests queued). '
        'Consider increasing maxQueueDepth or adding more instances.',
      );
    }
  }

  /// Merges the model config's [keepAlive] into [StreamChatOptions.backendOptions]
  /// unless the caller already set a `keep_alive` value.
  StreamChatOptions _injectModelKeepAlive(
    String model,
    StreamChatOptions? options,
  ) {
    final opts = options ?? const StreamChatOptions();
    final keepAlive = _configFor(model)?.keepAliveParam;
    if (keepAlive == null) return opts;

    final existing = opts.backendOptions;
    if (existing.containsKey('keep_alive') ||
        existing.containsKey('keepAlive')) {
      return opts;
    }
    return opts.copyWith(
      backendOptions: {...existing, 'keep_alive': keepAlive},
    );
  }

  /// Resolves the effective embedding isolation strategy and, when
  /// [EmbeddingIsolation.unloadFirst], injects `keep_alive: '0'` into the
  /// options map so [OllamaChatRepository.embed] sends it as a top-level
  /// body parameter.
  Map<String, dynamic> _injectEmbeddingKeepAlive(
    String model,
    _OllamaSlot slot,
    Map<String, dynamic> options,
  ) {
    // Model-level config overrides instance-level
    final modelConfig = _configFor(model);
    final isolation =
        modelConfig?.embeddingIsolation ?? slot.config.embeddingIsolation;

    // If caller already specified keep_alive, don't override
    if (options.containsKey('keep_alive') || options.containsKey('keepAlive')) {
      return options;
    }

    // Inject keepAlive from model config if set
    if (modelConfig?.keepAliveParam != null) {
      return {...options, 'keep_alive': modelConfig!.keepAliveParam};
    }

    // For unloadFirst: force embedding model to unload after use
    if (isolation == EmbeddingIsolation.unloadFirst) {
      return {...options, 'keep_alive': '0'};
    }

    return options;
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
        final client = http.Client();
        try {
          final response = await client
              .get(Uri.parse('${slot.config.baseUrl}/api/version'))
              .timeout(timeout);
          nowHealthy = response.statusCode == 200;
        } finally {
          client.close();
        }
      } catch (_) {
        nowHealthy = false;
      }

      slot.healthy = nowHealthy;
      if (wasHealthy != nowHealthy && !_stateController.isClosed) {
        _stateController.add(
          OllamaInstanceStateChange(
            baseUrl: slot.config.baseUrl,
            healthy: nowHealthy,
          ),
        );
      }
    }
  }
}
