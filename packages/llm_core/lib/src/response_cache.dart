import 'package:llm_core/src/llm_response.dart';

/// Interface for caching LLM responses.
///
/// Implementations can provide different caching strategies (in-memory, disk, etc.).
abstract class ResponseCache {
  /// Get a cached response for the given key.
  ///
  /// Returns the cached response if found, null otherwise.
  Future<LLMResponse?> get(String key);

  /// Store a response in the cache with the given key.
  ///
  /// [key] - Cache key (typically based on model, messages, and options).
  /// [response] - The response to cache.
  /// [ttl] - Time to live for the cached entry.
  Future<void> put(String key, LLMResponse response, {Duration? ttl});

  /// Remove a cached entry.
  Future<void> remove(String key);

  /// Clear all cached entries.
  Future<void> clear();

  /// Get cache statistics.
  CacheStats get stats;
}

/// Statistics about cache usage.
class CacheStats {
  /// Creates cache statistics.
  const CacheStats({
    this.hits = 0,
    this.misses = 0,
    this.size = 0,
    this.maxSize = 0,
  });

  /// Number of cache hits.
  final int hits;

  /// Number of cache misses.
  final int misses;

  /// Current number of entries in cache.
  final int size;

  /// Maximum number of entries allowed.
  final int maxSize;

  /// Hit rate (hits / (hits + misses)).
  double get hitRate {
    final total = hits + misses;
    return total > 0 ? hits / total : 0.0;
  }

  /// Create a copy with some fields changed.
  CacheStats copyWith({int? hits, int? misses, int? size, int? maxSize}) {
    return CacheStats(
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      size: size ?? this.size,
      maxSize: maxSize ?? this.maxSize,
    );
  }
}

/// In-memory response cache implementation.
///
/// Uses a simple LRU (Least Recently Used) eviction policy.
class MemoryResponseCache implements ResponseCache {
  /// Creates an in-memory response cache.
  ///
  /// [maxSize] - Maximum number of entries to cache (default: 100).
  /// [defaultTtl] - Default time to live for cached entries (default: 1 hour).
  MemoryResponseCache({
    this.maxSize = 100,
    this.defaultTtl = const Duration(hours: 1),
  });

  final int maxSize;
  final Duration defaultTtl;
  final _cache = <String, _CacheEntry>{};
  int _hits = 0;
  int _misses = 0;

  @override
  Future<LLMResponse?> get(String key) async {
    final entry = _cache[key];

    if (entry == null) {
      _misses++;
      return null;
    }

    // Check if entry has expired
    if (entry.expiresAt != null && DateTime.now().isAfter(entry.expiresAt!)) {
      _cache.remove(key);
      _misses++;
      return null;
    }

    // Move to end (LRU)
    _cache.remove(key);
    _cache[key] = entry;
    _hits++;
    return entry.response;
  }

  @override
  Future<void> put(String key, LLMResponse response, {Duration? ttl}) async {
    // Remove oldest entries if at capacity
    while (_cache.length >= maxSize) {
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }

    final expiresAt = ttl != null
        ? DateTime.now().add(ttl)
        : DateTime.now().add(defaultTtl);

    _cache[key] = _CacheEntry(response: response, expiresAt: expiresAt);
  }

  @override
  Future<void> remove(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _hits = 0;
    _misses = 0;
  }

  @override
  CacheStats get stats => CacheStats(
    hits: _hits,
    misses: _misses,
    size: _cache.length,
    maxSize: maxSize,
  );
}

/// Cache entry with expiration.
class _CacheEntry {
  const _CacheEntry({required this.response, this.expiresAt});

  final LLMResponse response;
  final DateTime? expiresAt;
}

/// Utility for generating cache keys from request parameters.
class CacheKeyGenerator {
  /// Generate a cache key from model name and messages.
  ///
  /// [model] - Model identifier.
  /// [messages] - List of messages.
  /// [optionsHash] - Optional hash of additional options.
  static String generateKey(
    String model,
    List<dynamic> messages, {
    String? optionsHash,
  }) {
    // Create a simple hash from model and messages
    final messagesHash = messages.map((m) => m.toString()).join('|');
    final key = '$model|$messagesHash';
    return optionsHash != null ? '$key|$optionsHash' : key;
  }
}
