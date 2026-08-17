/// Per-model request-shape rules for the Anthropic Messages API.
///
/// The Messages API removed two request shapes on newer models rather than
/// deprecating them, so sending the old shape is a hard `400` rather than a
/// silently ignored field:
///
/// | Request shape                                  | Modern models | Legacy models |
/// |------------------------------------------------|---------------|---------------|
/// | `thinking: {type: "enabled", budget_tokens: N}` | **400**       | supported     |
/// | `thinking: {type: "adaptive"}`                  | supported     | **400**       |
/// | `temperature` / `top_p` / `top_k`               | **400**       | supported     |
///
/// "Modern" here means Claude Opus 4.7 and later, Claude Sonnet 5, Claude
/// Fable 5, and Claude Mythos 5. Because every model released from Opus 4.7
/// onward follows the modern shape, an **unrecognized** model id is treated as
/// modern — a new model works without a library update, while the legacy set
/// is finite and enumerated below.
library;

import 'package:llm_core/llm_core.dart';

/// The request shape a given Claude model expects.
enum ClaudeRequestShape {
  /// Claude Opus 4.7+, Sonnet 5, Fable 5, Mythos 5.
  ///
  /// Adaptive thinking only; sampling parameters are rejected.
  modern,

  /// Claude Opus 4.6 and Sonnet 4.6.
  ///
  /// Adaptive thinking is supported and preferred; `budget_tokens` still works
  /// but is deprecated. Sampling parameters are accepted.
  transitional,

  /// Claude Opus 4.5 and earlier, Sonnet 4.5 and earlier, Haiku 4.5 and
  /// earlier, and the Claude 3 family.
  ///
  /// Thinking requires `budget_tokens`; adaptive thinking is not available.
  /// Sampling parameters are accepted.
  legacy,
}

/// Model ids (or id prefixes) that predate adaptive thinking.
///
/// Matched as prefixes so dated snapshots such as
/// `claude-haiku-4-5-20251001` resolve correctly.
const List<String> _legacyModelPrefixes = [
  'claude-opus-4-5',
  'claude-opus-4-1',
  'claude-opus-4-0',
  'claude-opus-4-20',
  'claude-sonnet-4-5',
  'claude-sonnet-4-0',
  'claude-sonnet-4-20',
  'claude-haiku-4-5',
  'claude-3',
  'claude-2',
  'claude-instant',
];

/// Model ids that accept both shapes; adaptive is preferred.
const List<String> _transitionalModelPrefixes = [
  'claude-opus-4-6',
  'claude-sonnet-4-6',
];

/// Resolves the request shape for [model].
///
/// Handles Amazon Bedrock's `anthropic.`-prefixed ids as well as first-party
/// ids. Unrecognized ids resolve to [ClaudeRequestShape.modern].
ClaudeRequestShape claudeRequestShapeFor(String model) {
  var id = model.toLowerCase().trim();
  if (id.startsWith('anthropic.')) {
    id = id.substring('anthropic.'.length);
  }
  for (final prefix in _transitionalModelPrefixes) {
    if (id.startsWith(prefix)) return ClaudeRequestShape.transitional;
  }
  for (final prefix in _legacyModelPrefixes) {
    if (id.startsWith(prefix)) return ClaudeRequestShape.legacy;
  }
  return ClaudeRequestShape.modern;
}

/// Whether [model] rejects `temperature`, `top_p` and `top_k` with a `400`.
bool claudeRejectsSamplingParams(String model) =>
    claudeRequestShapeFor(model) == ClaudeRequestShape.modern;

/// Whether [model] supports `thinking: {type: "adaptive"}`.
bool claudeSupportsAdaptiveThinking(String model) =>
    claudeRequestShapeFor(model) != ClaudeRequestShape.legacy;

/// Whether [model] supports native structured outputs via `output_config`.
///
/// Structured outputs are available on the modern and transitional families;
/// older models fall back to system-prompt injection.
bool claudeSupportsStructuredOutputs(String model) =>
    claudeRequestShapeFor(model) != ClaudeRequestShape.legacy;

/// Maps a token-denominated reasoning budget onto an `output_config.effort`
/// level for models that no longer accept `budget_tokens`.
///
/// The two are not equivalent — `budget_tokens` capped thinking alone, while
/// effort scales thinking *and* acting. This is a best-effort translation so a
/// caller that sets [reasoningBudget] still expresses relative depth rather
/// than having the value silently dropped.
String claudeEffortForBudget(int reasoningBudget) {
  if (reasoningBudget <= 2000) return 'low';
  if (reasoningBudget <= 8000) return 'medium';
  if (reasoningBudget <= 24000) return 'high';
  return 'max';
}

/// Maps a portable [ReasoningEffort] onto an `output_config.effort` value.
///
/// The API accepts low/medium/high/xhigh/max (xhigh model-dependent); the
/// levels below the API's floor clamp to `low`.
String claudeEffortWireValue(ReasoningEffort effort) => switch (effort) {
  ReasoningEffort.none ||
  ReasoningEffort.minimal ||
  ReasoningEffort.low => 'low',
  ReasoningEffort.medium => 'medium',
  ReasoningEffort.high => 'high',
  ReasoningEffort.xhigh => 'xhigh',
  ReasoningEffort.max => 'max',
};

/// Maps a portable [ReasoningEffort] onto a legacy `budget_tokens` value for
/// models that predate `output_config.effort`.
///
/// The inverse of [claudeEffortForBudget]'s thresholds; the API's minimum
/// accepted budget is 1024.
int claudeBudgetForEffort(ReasoningEffort effort) => switch (effort) {
  ReasoningEffort.none || ReasoningEffort.minimal => 1024,
  ReasoningEffort.low => 2000,
  ReasoningEffort.medium => 8000,
  ReasoningEffort.high => 16000,
  ReasoningEffort.xhigh => 24000,
  ReasoningEffort.max => 32000,
};
