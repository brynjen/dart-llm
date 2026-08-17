/// Known vLLM chat-completion request parameters, and validation for them.
///
/// ## Why this exists
///
/// vLLM **silently ignores request fields it does not recognize** — it returns
/// `200` and drops them rather than reporting an error. Combined with a
/// 64-parameter surface, that makes a typo indistinguishable from success:
/// `repitition_penalty` produces a perfectly normal response in which the
/// penalty was never applied.
///
/// Every other provider in this repo reports unknown fields, so this hazard is
/// specific to vLLM and is the reason `backendOptions` is validated here
/// instead of being forwarded blindly.
library;

/// Every parameter accepted by vLLM's `/v1/chat/completions` endpoint.
///
/// Generated from the `ChatCompletionRequest` schema published by a vLLM
/// server at `/openapi.json` (vLLM 0.27.1). Servers running a different
/// version may accept a slightly different set — see
/// `VLLMRepository.fetchSupportedParams` to validate against the actual
/// server rather than this snapshot.
const Set<String> knownVllmChatParams = {
  // OpenAI-compatible
  'frequency_penalty',
  'logit_bias',
  'logprobs',
  'max_completion_tokens',
  'max_tokens',
  'messages',
  'model',
  'n',
  'parallel_tool_calls',
  'presence_penalty',
  'reasoning_effort',
  'response_format',
  'seed',
  'stop',
  'stream',
  'stream_options',
  'temperature',
  'tool_choice',
  'tools',
  'top_logprobs',
  'top_p',
  'user',
  // vLLM sampling extensions
  'bad_words',
  'allowed_token_ids',
  'ignore_eos',
  'include_stop_str_in_output',
  'length_penalty',
  'min_p',
  'min_tokens',
  'repetition_detection',
  'repetition_penalty',
  'skip_special_tokens',
  'spaces_between_special_tokens',
  'stop_token_ids',
  'top_k',
  'truncate_prompt_tokens',
  'truncation_side',
  'use_beam_search',
  // vLLM prompt / template control
  'add_generation_prompt',
  'add_special_tokens',
  'chat_template',
  'chat_template_kwargs',
  'continue_final_message',
  'documents',
  'echo',
  'media_io_kwargs',
  'mm_processor_kwargs',
  // vLLM reasoning
  'include_reasoning',
  'thinking_token_budget',
  // vLLM structured output
  'structured_outputs',
  // vLLM output detail
  'logprob_token_ids',
  'prompt_logprobs',
  'return_assistant_tokens_mask',
  'return_prompt_text',
  'return_token_ids',
  'return_token_offsets',
  'return_tokens_as_token_ids',
  // vLLM request handling
  'cache_salt',
  'ec_transfer_params',
  'kv_transfer_params',
  'priority',
  'request_id',
  'stream_interval',
  'vllm_xargs',
};

/// Parameters this repository builds itself.
///
/// Setting one through `backendOptions` would either be silently overwritten
/// or would corrupt the request, so it is rejected instead.
const Set<String> reservedVllmParams = {
  'model',
  'messages',
  'stream',
  'stream_options',
};

/// Every parameter accepted by vLLM's `/v1/embeddings` endpoint.
///
/// From the `EmbeddingChatRequest`/`EmbeddingCompletionRequest` schemas
/// published at `/openapi.json` (vLLM 0.27.1). Kept separate from
/// [knownVllmChatParams] because the two endpoints share almost nothing —
/// validating embedding options against the chat schema would accept
/// sampling parameters the embeddings endpoint silently drops.
const Set<String> knownVllmEmbeddingParams = {
  'dimensions',
  'encoding_format',
  'priority',
  'request_id',
  'truncate_prompt_tokens',
  'user',
};

/// Parameters `embed`/`batchEmbed` build themselves; rejected in `options`.
const Set<String> reservedVllmEmbeddingParams = {'model', 'input'};

/// camelCase spellings accepted as aliases for their snake_case wire names.
///
/// Dart callers reach for camelCase by habit, and vLLM would silently drop it.
/// `llm_ollama` accepts the same aliases, so the behavior is consistent across
/// backends in this repo.
const Map<String, String> vllmParamAliases = {
  'topP': 'top_p',
  'topK': 'top_k',
  'minP': 'min_p',
  'maxTokens': 'max_tokens',
  'maxCompletionTokens': 'max_completion_tokens',
  'stopSequences': 'stop',
  'stopTokenIds': 'stop_token_ids',
  'repetitionPenalty': 'repetition_penalty',
  'presencePenalty': 'presence_penalty',
  'frequencyPenalty': 'frequency_penalty',
  'lengthPenalty': 'length_penalty',
  'minTokens': 'min_tokens',
  'ignoreEos': 'ignore_eos',
  'skipSpecialTokens': 'skip_special_tokens',
  'badWords': 'bad_words',
  'logitBias': 'logit_bias',
  'topLogprobs': 'top_logprobs',
  'promptLogprobs': 'prompt_logprobs',
  'truncatePromptTokens': 'truncate_prompt_tokens',
  'chatTemplate': 'chat_template',
  'chatTemplateKwargs': 'chat_template_kwargs',
  'structuredOutputs': 'structured_outputs',
  'thinkingTokenBudget': 'thinking_token_budget',
  'includeReasoning': 'include_reasoning',
  'toolChoice': 'tool_choice',
  'parallelToolCalls': 'parallel_tool_calls',
  'cacheSalt': 'cache_salt',
  'vllmXargs': 'vllm_xargs',
  'encodingFormat': 'encoding_format',
  'requestId': 'request_id',
};

/// Guided-decoding parameter names removed in vLLM 0.12.
///
/// The server ignores these silently, so a request carrying one returns
/// unconstrained output with no error.
const Set<String> legacyGuidedKeys = {
  'guided_json',
  'guided_regex',
  'guided_choice',
  'guided_grammar',
  'guided_whitespace_pattern',
  'guided_decoding_backend',
};

/// Outcome of validating one `backendOptions` entry.
enum VllmParamIssue {
  /// The repository builds this field itself.
  reserved,

  /// Removed in vLLM 0.12; silently ignored by the server.
  legacyGuided,

  /// Not a recognized vLLM parameter; would be silently dropped.
  unknown,
}

/// A rejected `backendOptions` entry, with a suggested correction.
class VllmParamValidationError {
  const VllmParamValidationError({
    required this.key,
    required this.issue,
    this.suggestion,
    this.path = 'backendOptions',
  });

  /// The offending key, as written by the caller.
  final String key;

  /// Why it was rejected.
  final VllmParamIssue issue;

  /// Closest known parameter, when one is near enough to be a likely typo.
  final String? suggestion;

  /// Where the key appeared, e.g. `backendOptions.extra_body`.
  final String path;

  /// A message naming the problem and the fix.
  String get message => switch (issue) {
    VllmParamIssue.reserved =>
      '"$key" is built by VLLMChatRepository and cannot be set through $path.',
    VllmParamIssue.legacyGuided =>
      '"$key" was removed in vLLM 0.12. The server ignores it silently and '
          'returns unconstrained output rather than an error. Use '
          'VLLMStructuredOutputs.${key.replaceFirst('guided_', '')}(...) instead.',
    VllmParamIssue.unknown =>
      'vLLM does not recognize "$key" and silently drops unknown fields, so '
          'this would have no effect.'
          '${suggestion != null ? ' Did you mean "$suggestion"?' : ''}'
          ' If your server build does accept it, pass it through '
          '"vllm_xargs" instead.',
  };

  @override
  String toString() => message;
}

/// Normalizes a caller-supplied key to its wire name.
String normalizeVllmParam(String key) => vllmParamAliases[key] ?? key;

/// Returns a copy of [options] with every key normalized to its wire name
/// and a nested `extra_body` map flattened into the top level.
///
/// Run this *after* [validateVllmParams] — validation works on the raw map so
/// its error messages show the caller's own spelling. Everything downstream
/// of validation must read from the normalized map; reading the raw map by
/// wire name is how an aliased key (`toolChoice`) passes validation and then
/// silently never reaches the request.
///
/// On duplicate keys after normalization (`topP` alongside `top_p`, or a key
/// repeated inside `extra_body`), the later entry wins — same as `Map`
/// literal semantics.
Map<String, dynamic> normalizeVllmParams(Map<String, dynamic> options) {
  final normalized = <String, dynamic>{};
  for (final entry in options.entries) {
    if (entry.key == 'extra_body' && entry.value is Map<String, dynamic>) {
      normalized.addAll(
        normalizeVllmParams(entry.value as Map<String, dynamic>),
      );
      continue;
    }
    normalized[normalizeVllmParam(entry.key)] = entry.value;
  }
  return normalized;
}

/// Validates [options], returning every problem found.
///
/// Recurses into a nested `extra_body` map, which callers coming from the
/// OpenAI Python SDK often reach for even though vLLM never reads it.
///
/// Pass [knownParams] to validate against a specific server's schema (see
/// `VLLMRepository.fetchSupportedParams`); defaults to the snapshot in
/// [knownVllmChatParams]. [reservedParams] defaults to [reservedVllmParams];
/// pass [reservedVllmEmbeddingParams] when validating embedding options.
List<VllmParamValidationError> validateVllmParams(
  Map<String, dynamic> options, {
  Set<String>? knownParams,
  Set<String>? reservedParams,
  String path = 'backendOptions',
}) {
  final known = knownParams ?? knownVllmChatParams;
  final reserved = reservedParams ?? reservedVllmParams;
  final errors = <VllmParamValidationError>[];

  for (final entry in options.entries) {
    if (entry.key == 'extra_body' && entry.value is Map<String, dynamic>) {
      errors.addAll(
        validateVllmParams(
          entry.value as Map<String, dynamic>,
          knownParams: known,
          reservedParams: reserved,
          path: '$path.extra_body',
        ),
      );
      continue;
    }

    final key = normalizeVllmParam(entry.key);

    if (reserved.contains(key)) {
      errors.add(
        VllmParamValidationError(
          key: entry.key,
          issue: VllmParamIssue.reserved,
          path: path,
        ),
      );
    } else if (legacyGuidedKeys.contains(key)) {
      errors.add(
        VllmParamValidationError(
          key: entry.key,
          issue: VllmParamIssue.legacyGuided,
          path: path,
        ),
      );
    } else if (!known.contains(key)) {
      errors.add(
        VllmParamValidationError(
          key: entry.key,
          issue: VllmParamIssue.unknown,
          suggestion: suggestVllmParam(entry.key, known: known),
          path: path,
        ),
      );
    }
  }
  return errors;
}

/// Canonical ordering of reasoning-effort levels, weakest first.
const List<String> _effortLadder = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

/// Remaps a rejected `reasoning_effort` value to the nearest level the model
/// supports, or `null` when [errorBody] is not that rejection.
///
/// vLLM's request schema advertises the full effort enum, but each served
/// model validates against its **own** vocabulary and rejects the rest with a
/// 400 like:
///
/// > Bad request: Unexpected reasoning effort high. Supported types are
/// > xhigh (default), medium, and low.
///
/// (Qwen3.8, for example, takes low/medium/xhigh — no `high`.) That error is
/// the only place the vocabulary is discoverable, so the caller retries once
/// with the remapped value: the smallest supported level at or above the
/// requested one, else the largest supported level below it.
String? remapVllmReasoningEffort(String requested, String errorBody) {
  if (!RegExp(r'[Uu]nexpected reasoning effort').hasMatch(errorBody)) {
    return null;
  }
  final supportedPart = errorBody.split(RegExp(r'[Ss]upported'));
  if (supportedPart.length < 2) return null;
  final vocabulary = supportedPart.sublist(1).join();

  // Word-bounded so 'high' does not match inside 'xhigh'.
  final supported = _effortLadder
      .where((level) => RegExp('\\b$level\\b').hasMatch(vocabulary))
      .toSet();
  supported.remove(requested); // the server just rejected it
  if (supported.isEmpty) return null;

  final want = _effortLadder.indexOf(requested);
  if (want == -1) return null;

  String? best;
  for (final level in _effortLadder) {
    if (!supported.contains(level)) continue;
    best = level;
    if (_effortLadder.indexOf(level) >= want) break;
  }
  return best;
}

/// Closest known parameter to [key], or `null` when nothing is close enough.
///
/// Uses Levenshtein distance with a threshold that scales with key length, so
/// short keys do not match wildly different ones.
String? suggestVllmParam(String key, {Set<String>? known}) {
  final candidates = known ?? knownVllmChatParams;
  final needle = key.toLowerCase();
  final threshold = (needle.length / 3).ceil().clamp(1, 4);

  String? best;
  var bestDistance = threshold + 1;
  for (final candidate in candidates) {
    final d = _levenshtein(needle, candidate);
    if (d < bestDistance) {
      bestDistance = d;
      best = candidate;
    }
  }
  return bestDistance <= threshold ? best : null;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final deletion = previous[j + 1] + 1;
      final insertion = current[j] + 1;
      final substitution = previous[j] + cost;
      current[j + 1] = deletion < insertion
          ? (deletion < substitution ? deletion : substitution)
          : (insertion < substitution ? insertion : substitution);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}
