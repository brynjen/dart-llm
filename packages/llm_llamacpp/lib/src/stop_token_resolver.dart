/// Resolves the text-level stop strings used to end a generation.
///
/// Two mechanisms stop generation in llama.cpp. Token-level detection uses
/// `llama_vocab_is_eog`, which only flags the tokens the GGUF marks as
/// end-of-generation. Text-level detection matches strings against the
/// generated text, and it is what catches models whose turn-end marker is not
/// flagged as EOG -- without it those models generate until `maxTokens` and the
/// response looks truncated.
///
/// [requested] are caller-supplied stops (see `LlamaCppChatRepository.stopTokens`).
/// They are *additive*: the markers detected from [prompt] are appended to them,
/// never substituted for them, so supplying a stop for one model family cannot
/// disable detection for another. Duplicates are dropped, so naming a marker
/// that would have been auto-detected anyway is a no-op.
///
/// [onDiagnostic], when given, is called with a human-readable note for each
/// marker added by detection.
List<String> resolveStopTokens({
  required List<String> requested,
  required String prompt,
  void Function(String message)? onDiagnostic,
}) {
  final resolved = <String>[...requested];

  void addDetected(String marker, String reason) {
    if (resolved.contains(marker)) {
      return;
    }
    resolved.add(marker);
    onDiagnostic?.call('Auto-added "$marker" to stop tokens ($reason).');
  }

  // Many models use ChatML-style turn boundaries (`<|im_end|>`) but ship GGUFs
  // where llama_vocab_is_eog only flags the model-level EOS token. When the
  // chat template renders to `<|im_start|>...<|im_end|>` we add `<|im_end|>` as
  // an explicit stop string so generation actually stops at the end of the
  // assistant turn instead of running to maxTokens.
  if (prompt.contains('<|im_end|>') || prompt.contains('<|im_start|>')) {
    addDetected('<|im_end|>', 'ChatML-style template detected');
  }

  // Same idea for Llama-3-style end-of-turn markers.
  if (prompt.contains('<|eot_id|>')) {
    addDetected('<|eot_id|>', 'Llama-3-style template detected');
  }

  return resolved;
}
