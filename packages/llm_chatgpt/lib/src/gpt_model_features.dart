/// Per-model request-shape rules for the OpenAI Chat Completions API.
///
/// OpenAI splits its lineup into reasoning models (o-series, gpt-5 family)
/// and conventional models (gpt-4o and friends), and the two reject each
/// other's parameters with a hard `400`:
///
/// | Request shape          | Reasoning models | Conventional models |
/// |------------------------|------------------|---------------------|
/// | `reasoning_effort`     | supported*       | **400**             |
/// | `temperature` / `top_p`| **400**          | supported           |
///
/// *`o1-mini` and `o1-preview` are reasoning models that predate the
/// `reasoning_effort` parameter and reject it.
///
/// Because sending `reasoning_effort` to a conventional model is a hard error
/// while omitting it on a reasoning model merely uses the server default, an
/// **unrecognized** model id is treated as conventional — the deliberate
/// opposite of `claudeRequestShapeFor`'s forward-safe default. The reasoning
/// families are finite and enumerated below; supported effort values are a
/// snapshot and clamped per family in [gptEffortWireValue].
library;

import 'package:llm_core/llm_core.dart';

/// Reasoning-model id prefixes.
const List<String> _reasoningModelPrefixes = ['o1', 'o3', 'o4', 'gpt-5'];

/// Ids inside the reasoning prefixes that are NOT reasoning models.
const List<String> _reasoningModelExclusions = ['gpt-5-chat'];

/// Reasoning models that reject `reasoning_effort` entirely.
const List<String> _noEffortParamPrefixes = ['o1-mini', 'o1-preview'];

String _normalize(String model) => model.toLowerCase().trim();

bool _hasPrefix(String id, List<String> prefixes) =>
    prefixes.any(id.startsWith);

/// Whether [model] is an OpenAI reasoning model (o-series or gpt-5 family,
/// excluding the non-reasoning `gpt-5-chat` ids).
bool gptIsReasoningModel(String model) {
  final id = _normalize(model);
  if (_hasPrefix(id, _reasoningModelExclusions)) return false;
  return _hasPrefix(id, _reasoningModelPrefixes);
}

/// Whether [model] accepts the `reasoning_effort` parameter.
bool gptSupportsReasoningEffort(String model) {
  final id = _normalize(model);
  if (!gptIsReasoningModel(id)) return false;
  return !_hasPrefix(id, _noEffortParamPrefixes);
}

/// Whether [model] rejects `temperature` and `top_p` with a `400`.
bool gptRejectsSamplingParams(String model) => gptIsReasoningModel(model);

/// Maps a portable [ReasoningEffort] onto the `reasoning_effort` value the
/// given model family accepts, or null when [model] does not take the
/// parameter at all.
///
/// Supported values per family (API snapshot):
///
/// | Family            | Values                              |
/// |-------------------|-------------------------------------|
/// | o-series          | low, medium, high                   |
/// | gpt-5 / gpt-5.0   | minimal, low, medium, high          |
/// | gpt-5.1 and later | none, low, medium, high (+ xhigh on codex-max) |
///
/// Out-of-range values are clamped to the nearest supported level rather
/// than rejected, so portable code can use the full scale.
String? gptEffortWireValue(String model, ReasoningEffort effort) {
  final id = _normalize(model);
  if (!gptSupportsReasoningEffort(id)) return null;

  if (_hasPrefix(id, const ['o1', 'o3', 'o4'])) {
    return switch (effort) {
      ReasoningEffort.none ||
      ReasoningEffort.minimal ||
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high ||
      ReasoningEffort.xhigh ||
      ReasoningEffort.max => 'high',
    };
  }

  // gpt-5 family. Ids like `gpt-5-nano` / `gpt-5-2025-08-07` are the original
  // generation (supports `minimal`, not `none`); `gpt-5.1+` swapped `minimal`
  // for `none` and added `xhigh` on codex-max variants.
  final laterGeneration = RegExp(r'^gpt-5\.[1-9]').hasMatch(id);
  if (laterGeneration) {
    final supportsXhigh = id.contains('codex-max');
    return switch (effort) {
      ReasoningEffort.none => 'none',
      ReasoningEffort.minimal || ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh ||
      ReasoningEffort.max => supportsXhigh ? 'xhigh' : 'high',
    };
  }
  return switch (effort) {
    ReasoningEffort.none || ReasoningEffort.minimal => 'minimal',
    ReasoningEffort.low => 'low',
    ReasoningEffort.medium => 'medium',
    ReasoningEffort.high ||
    ReasoningEffort.xhigh ||
    ReasoningEffort.max => 'high',
  };
}
