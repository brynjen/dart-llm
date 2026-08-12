/// Per-model constraints applied globally across all instances in a [VLLMPool].
class VLLMModelConfig {
  const VLLMModelConfig({
    required this.pattern,
    this.maxConcurrent,
    this.exclusive = false,
  });

  /// Pattern for matching model names. Supports exact match and `*` wildcard.
  final String pattern;

  /// Maximum number of simultaneous requests for this model across all
  /// instances. `null` means no additional limit beyond per-instance capacity.
  final int? maxConcurrent;

  /// When `true`, forces a global concurrency limit of 1 for matching models.
  final bool exclusive;

  /// Returns `true` if [model] matches this config's [pattern].
  bool matches(String model) {
    if (!pattern.contains('*')) return pattern == model;
    final regexStr =
        '^${pattern.replaceAll('.', r'\.').replaceAll('*', '.*')}\$';
    return RegExp(regexStr).hasMatch(model);
  }
}
