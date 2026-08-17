/// Portable reasoning-depth levels.
///
/// This is the union of the effort scales exposed by the supported backends;
/// each backend clamps to the subset its API accepts and documents the
/// clamping in its package README. [none] actively suppresses thinking where
/// the backend can express that, which is different from leaving
/// `reasoningEffort` unset (`null`): unset sends no reasoning parameter at
/// all, deferring to the provider's default.
enum ReasoningEffort {
  /// Suppress thinking entirely where the backend can express it.
  none,

  /// The smallest amount of reasoning the backend supports.
  minimal,

  /// Low reasoning depth.
  low,

  /// Medium reasoning depth.
  medium,

  /// High reasoning depth.
  high,

  /// Extra-high reasoning depth.
  xhigh,

  /// The largest amount of reasoning the backend supports.
  max;

  /// Wire string (`'none'`..`'max'`).
  ///
  /// Backends clamp to their supported subset before sending.
  String get wireName => name;
}

/// Canonical mapping from a reasoning token budget to a portable effort level.
///
/// Used by backends that have no native token budget (OpenAI, Ollama) to
/// honor [reasoningBudget] as an effort level instead. The bands are
/// power-of-two ranges bracketing the thresholds the budget-native backends
/// already use.
ReasoningEffort reasoningEffortForBudget(int budget) {
  if (budget <= 0) return ReasoningEffort.none;
  if (budget <= 512) return ReasoningEffort.minimal;
  if (budget <= 2048) return ReasoningEffort.low;
  if (budget <= 8192) return ReasoningEffort.medium;
  if (budget <= 24576) return ReasoningEffort.high;
  if (budget <= 49152) return ReasoningEffort.xhigh;
  return ReasoningEffort.max;
}
