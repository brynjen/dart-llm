import 'package:llm_ollama/src/pool/ollama_instance_config.dart';

/// Per-model constraints applied globally across all instances in an
/// [OllamaPool].
///
/// Model configs are matched against request model names using [pattern],
/// which supports exact strings and simple glob wildcards (`*`).
///
/// Example — restrict a 70B model to one concurrent request and unload
/// immediately after use:
/// ```dart
/// OllamaModelConfig(
///   pattern: 'llama3.3:70b',
///   maxConcurrent: 1,
///   exclusive: true,
///   keepAlive: Duration.zero,
/// )
/// ```
///
/// Example — allow up to 3 concurrent 4B models:
/// ```dart
/// OllamaModelConfig(pattern: '*:4b', maxConcurrent: 3)
/// ```
///
/// Example — keep embedding models loaded for 30 minutes:
/// ```dart
/// OllamaModelConfig(
///   pattern: '*embed*',
///   keepAlive: Duration(minutes: 30),
/// )
/// ```
class OllamaModelConfig {
  const OllamaModelConfig({
    required this.pattern,
    this.maxConcurrent,
    this.exclusive = false,
    this.keepAlive,
    this.embeddingIsolation,
  });

  /// Pattern for matching model names. Supports exact match and `*` wildcard.
  ///
  /// Examples: `'llama3.3:70b'`, `'*:4b'`, `'*embed*'`, `'qwen*'`.
  final String pattern;

  /// Maximum number of simultaneous requests for this model across ALL
  /// instances in the pool.
  ///
  /// `null` means no additional limit beyond the per-instance [maxConcurrent].
  final int? maxConcurrent;

  /// When `true`, while this model is running on an instance no other model
  /// may start on that same instance.
  ///
  /// Use this for models that fill an entire GPU card. Implies
  /// [maxConcurrent] of 1 on any given instance.
  final bool exclusive;

  /// How long to keep this model loaded after a request completes.
  ///
  /// Injected as the `keep_alive` field in every request for this model:
  /// - `Duration.zero` → unload immediately (`keep_alive: '0'`)
  /// - `Duration(minutes: 5)` → stay loaded 5 minutes (`keep_alive: '300s'`)
  /// - `null` → use Ollama's default (5 minutes)
  ///
  /// Can be overridden per-request via `backendOptions: {'keep_alive': ...}`.
  final Duration? keepAlive;

  /// Per-model embedding isolation strategy. Overrides the instance-level
  /// setting when set.
  final EmbeddingIsolation? embeddingIsolation;

  /// Returns `true` if [model] matches this config's [pattern].
  bool matches(String model) {
    if (!pattern.contains('*')) return pattern == model;
    // Convert glob to regex: escape dots, replace * with .*
    final regexStr =
        '^${pattern.replaceAll('.', r'\.').replaceAll('*', '.*')}\$';
    return RegExp(regexStr).hasMatch(model);
  }

  /// The `keep_alive` value to inject into Ollama requests, or `null` if
  /// [keepAlive] is not set.
  String? get keepAliveParam {
    if (keepAlive == null) return null;
    if (keepAlive == Duration.zero) return '0';
    return '${keepAlive!.inSeconds}s';
  }
}
