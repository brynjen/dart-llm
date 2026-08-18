import 'package:llm_llamacpp/src/tool_calls/pythonic_arguments.dart';

/// How a model family encodes tool calls in its raw token stream.
///
/// Hosted APIs hand back structured tool calls, so this problem is specific to
/// running a model locally: all llama.cpp gives us is detokenized text, and
/// every model family wraps its calls differently. Upstream solves this in
/// `common/chat.cpp`, but that is C++ behind `LLAMA_BUILD_COMMON`, which this
/// package deliberately does not build — so the equivalent lives here in Dart.
///
/// The set below covers the families that are realistic to run on-device. To add
/// another, give it delimiters, say whether its payload is Pythonic or JSON, and
/// list it in [delimited]; the parser and the stream handler both derive their
/// behaviour from that.
enum ToolCallFormat {
  /// Liquid AI LFM2 / LFM2.5.
  ///
  /// `<|tool_call_start|>[fn(a=1, b='x')]<|tool_call_end|>` — Pythonic calls,
  /// single-quoted strings, Python `True`/`False`/`None`.
  /// See https://docs.liquid.ai/lfm/key-concepts/tool-use
  lfm2,

  /// Hermes / Qwen and most ChatML tool-tuned models.
  ///
  /// `<tool_call>{"name": "fn", "arguments": {...}}</tool_call>`, repeated once
  /// per call.
  hermes,

  /// Mistral / Mixtral.
  ///
  /// `[TOOL_CALLS][{"name": "fn", "arguments": {...}}]`
  mistral,

  /// Llama 3.1 / 3.2 Pythonic calls behind a python tag.
  ///
  /// `<|python_tag|>fn(a=1)`
  llama3Pythonic,

  /// Bare Pythonic calls with no wrapper: `[fn(a=1)]`.
  pythonic,

  /// Bare JSON with no wrapper: `{"name": "fn", "arguments": {...}}`.
  ///
  /// The fallback, and what a model produces when the prompt simply asks it to
  /// reply with JSON.
  json;

  /// The delimiter pair wrapping tool calls, or null for the bare formats.
  ///
  /// An empty close means the payload runs to the end of the output.
  (String open, String close)? get delimiters => switch (this) {
    lfm2 => ('<|tool_call_start|>', '<|tool_call_end|>'),
    hermes => ('<tool_call>', '</tool_call>'),
    mistral => ('[TOOL_CALLS]', ''),
    llama3Pythonic => ('<|python_tag|>', ''),
    pythonic => null,
    json => null,
  };

  /// Whether the payload inside the delimiters is Pythonic rather than JSON.
  bool get isPythonic =>
      this == lfm2 || this == llama3Pythonic || this == pythonic;

  /// Formats that announce themselves with an opening delimiter.
  ///
  /// Ordered so longer, more specific openers are tested first.
  static const List<ToolCallFormat> delimited = [
    lfm2,
    hermes,
    mistral,
    llama3Pythonic,
  ];

  /// Every opening delimiter, for the stream handler to watch for.
  static List<String> get openingDelimiters => [
    for (final f in delimited) f.delimiters!.$1,
  ];

  /// Infers the family from a GGUF chat template.
  ///
  /// The template is the most reliable signal available locally: it is what the
  /// model was trained to emit, and it ships inside the GGUF. Returns null when
  /// nothing matches, in which case callers fall back to content detection.
  static ToolCallFormat? detectFromChatTemplate(String? template) {
    if (template == null || template.isEmpty) return null;

    // Match on emitted delimiters rather than model names: templates get copied
    // between fine-tunes, but a template that writes `<|tool_call_start|>` is by
    // construction an LFM2-style template.
    for (final format in delimited) {
      if (template.contains(format.delimiters!.$1)) return format;
    }

    // Hermes-family templates sometimes only mention the closing tag or the
    // tool-list wrapper.
    if (template.contains('</tool_call>') || template.contains('<tools>')) {
      return hermes;
    }
    return null;
  }

  /// Infers the family from generated content.
  ///
  /// Used when no chat template was available, and as a cross-check: a model can
  /// emit its native format even when the prompt asked for something else.
  static ToolCallFormat? detectFromContent(String content) {
    for (final format in delimited) {
      if (content.contains(format.delimiters!.$1)) return format;
    }
    if (content.contains('</tool_call>')) return hermes;
    if (looksLikePythonicCallList(content)) return pythonic;
    return null;
  }
}
