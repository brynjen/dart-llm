/// Typed access to the vLLM sampling parameters that have no cross-provider
/// equivalent in `LLMChatOptions`.
///
/// vLLM accepts 64 request parameters. Typing all of them would be a
/// maintenance treadmill that breaks on every vLLM release, so this covers the
/// handful that are actually reached for and leaves the long tail to
/// `LLMChatOptions.backendOptions` — which is validated against
/// [knownVllmChatParams], so a typo there is still caught.
///
/// Use `LLMChatOptions` for anything portable (`temperature`, `topP`, `topK`,
/// `maxOutputTokens`, `stopSequences`); use this for the vLLM-only knobs.
///
/// ```dart
/// repo.streamChat(
///   'Qwen/Qwen3-0.6B',
///   messages: messages,
///   options: LLMChatOptions(
///     temperature: 0.2, // portable
///     backendOptions: const VLLMSamplingOptions(
///       minP: 0.05, // vLLM-only
///       repetitionPenalty: 1.05,
///     ).toBackendOptions(),
///   ),
/// );
/// ```
library;

/// vLLM-specific sampling parameters.
///
/// Every field is optional; only the ones you set are sent.
class VLLMSamplingOptions {
  const VLLMSamplingOptions({
    this.minP,
    this.repetitionPenalty,
    this.presencePenalty,
    this.frequencyPenalty,
    this.lengthPenalty,
    this.minTokens,
    this.seed,
    this.ignoreEos,
    this.stopTokenIds,
    this.includeStopStrInOutput,
    this.badWords,
    this.skipSpecialTokens,
    this.truncatePromptTokens,
    this.vllmXargs,
  });

  /// Minimum-probability cutoff, relative to the most likely token.
  final double? minP;

  /// Penalty applied to tokens already present. `> 1.0` discourages repeats.
  final double? repetitionPenalty;

  /// OpenAI-compatible presence penalty.
  final double? presencePenalty;

  /// OpenAI-compatible frequency penalty.
  final double? frequencyPenalty;

  /// Beam-search length penalty. Only meaningful with beam search enabled.
  final double? lengthPenalty;

  /// Minimum number of tokens to generate before a stop condition may apply.
  final int? minTokens;

  /// Seed for reproducible sampling.
  final int? seed;

  /// Continue generating past the EOS token.
  final bool? ignoreEos;

  /// Token ids that terminate generation, in addition to `stop` strings.
  final List<int>? stopTokenIds;

  /// Include the matched stop string in the returned text.
  final bool? includeStopStrInOutput;

  /// Strings the model must not produce.
  final List<String>? badWords;

  /// Strip special tokens from the output. Defaults to `true` server-side.
  final bool? skipSpecialTokens;

  /// Truncate the prompt to this many tokens before generating.
  final int? truncatePromptTokens;

  // `n` (multiple completions) is deliberately not exposed. `LLMChunk` carries
  // a single message, and the stream converter reads `choices[0]` only, so
  // requesting several candidates would silently return one. Set it through
  // `backendOptions` if you are consuming the raw stream yourself and
  // understand that extra choices are dropped.

  /// Passthrough for parameters added by custom vLLM extensions.
  ///
  /// This is vLLM's own escape hatch for values it cannot know about ahead of
  /// time. Unlike an unrecognized top-level key — which vLLM silently drops —
  /// `vllm_xargs` is a declared field, so values placed here reach the server.
  /// Values must be strings or numbers.
  final Map<String, Object>? vllmXargs;

  /// The wire representation, using vLLM's snake_case field names.
  Map<String, dynamic> toJson() => {
    if (minP != null) 'min_p': minP,
    if (repetitionPenalty != null) 'repetition_penalty': repetitionPenalty,
    if (presencePenalty != null) 'presence_penalty': presencePenalty,
    if (frequencyPenalty != null) 'frequency_penalty': frequencyPenalty,
    if (lengthPenalty != null) 'length_penalty': lengthPenalty,
    if (minTokens != null) 'min_tokens': minTokens,
    if (seed != null) 'seed': seed,
    if (ignoreEos != null) 'ignore_eos': ignoreEos,
    if (stopTokenIds != null) 'stop_token_ids': stopTokenIds,
    if (includeStopStrInOutput != null)
      'include_stop_str_in_output': includeStopStrInOutput,
    if (badWords != null) 'bad_words': badWords,
    if (skipSpecialTokens != null) 'skip_special_tokens': skipSpecialTokens,
    if (truncatePromptTokens != null)
      'truncate_prompt_tokens': truncatePromptTokens,
    if (vllmXargs != null) 'vllm_xargs': vllmXargs,
  };

  /// The map shape accepted by `LLMChatOptions.backendOptions`.
  ///
  /// Merge with other helpers using the spread operator:
  ///
  /// ```dart
  /// backendOptions: {
  ///   ...const VLLMSamplingOptions(minP: 0.05).toBackendOptions(),
  ///   ...const VLLMStructuredOutputs.choice(['yes', 'no']).toBackendOptions(),
  /// },
  /// ```
  Map<String, dynamic> toBackendOptions() => toJson();
}
