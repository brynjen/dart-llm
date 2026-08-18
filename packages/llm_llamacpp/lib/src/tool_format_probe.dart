part of 'persistent_inference_isolate.dart';

/// Infers the tool-call family a model was trained on.
///
/// The chat template is checked first, but it is not sufficient on its own:
/// GGUF conversions frequently ship a trimmed template. LiquidAI's
/// `LFM2.5-1.2B-Instruct-Q4_K_M.gguf`, for example, embeds a 1783-character
/// template with no `{%- if tools -%}` branch at all, while the template in the
/// source repo is 5487 characters and renders `<|tool_call_start|>`. A model
/// whose template omits tools still emits its native tool syntax, because that
/// behaviour lives in the weights.
///
/// So when the template says nothing, the vocabulary is asked instead: if a
/// family's opening delimiter tokenizes to exactly one token, that token is in the
/// model's vocab as a special token, which only happens when the model was
/// trained with it.
ToolCallFormat _detectToolCallFormat(
  LlamaBindings bindings,
  ffi.Pointer<llama_model> model,
  String? chatTemplate,
) {
  final fromTemplate = ToolCallFormat.detectFromChatTemplate(chatTemplate);
  if (fromTemplate != null) return fromTemplate;

  final vocab = bindings.llama_model_get_vocab(model);
  if (vocab.address == 0) return ToolCallFormat.json;

  for (final format in ToolCallFormat.delimited) {
    if (_isSingleSpecialToken(bindings, vocab, format.delimiters!.$1)) {
      return format;
    }
  }

  return ToolCallFormat.json;
}

/// Whether [text] is a single token in [vocab] when special tokens are parsed.
bool _isSingleSpecialToken(
  LlamaBindings bindings,
  ffi.Pointer<llama_vocab> vocab,
  String text,
) {
  final textPtr = text.toNativeUtf8();
  final byteLen = utf8.encode(text).length;
  // Two slots is enough to tell "exactly one token" from "more than one".
  final tokens = calloc<llama_token>(2);
  try {
    final count = bindings.llama_tokenize(
      vocab,
      textPtr.cast(),
      byteLen,
      tokens,
      2,
      // No BOS, and do parse special tokens — that is the whole point.
      false,
      true,
    );
    // A negative return is llama.cpp reporting the required buffer size, i.e.
    // the text needed more than two tokens, so it is not a single special token.
    return count == 1;
  } finally {
    calloc.free(textPtr);
    calloc.free(tokens);
  }
}
