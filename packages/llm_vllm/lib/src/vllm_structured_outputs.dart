/// vLLM-native guided decoding (`structured_outputs`).
///
/// This is distinct from the OpenAI-compatible `response_format` field that
/// [LLMResponseFormat] maps to. Use `response_format` for JSON and JSON Schema;
/// use [VLLMStructuredOutputs] for the vLLM-specific constraint modes that have
/// no OpenAI equivalent — regex, a fixed choice set, or a context-free grammar.
///
/// ## Why this exists
///
/// vLLM 0.12 renamed the guided-decoding parameters:
///
/// | Removed          | Replacement                              |
/// |------------------|------------------------------------------|
/// | `guided_json`    | `structured_outputs: {"json": ...}`      |
/// | `guided_regex`   | `structured_outputs: {"regex": ...}`     |
/// | `guided_choice`  | `structured_outputs: {"choice": [...]}`  |
/// | `guided_grammar` | `structured_outputs: {"grammar": ...}`   |
///
/// The old names are **not** rejected — the server ignores unknown fields and
/// returns unconstrained output with a 200 status. A request built with the old
/// names therefore looks like it worked while silently producing free-form
/// text. [VLLMStructuredOutputs] emits the current field names, and
/// [assertNoLegacyGuidedKeys] rejects the old ones outright rather than letting
/// them fail silently.
///
/// These parameters go at the **top level** of the request body. `extra_body`
/// is an OpenAI Python SDK concept, not a wire field; vLLM ignores it.
///
/// ```dart
/// final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');
/// await repo.chatResponse(
///   'Qwen/Qwen3-0.6B',
///   messages: [LLMMessage(role: LLMRole.user, content: 'Is this positive?')],
///   options: LLMChatOptions(
///     backendOptions: VLLMStructuredOutputs.choice(['positive', 'negative'])
///         .toBackendOptions(),
///   ),
/// );
/// ```
library;

/// A vLLM guided-decoding constraint.
class VLLMStructuredOutputs {
  const VLLMStructuredOutputs._(
    this._key,
    this._value, {
    this.whitespacePattern,
  });

  /// Constrain output to valid JSON matching [schema].
  ///
  /// Prefer `LLMChatOptions.responseFormat` with a [JsonSchemaFormat] unless
  /// you specifically need this alongside another vLLM-only option.
  const VLLMStructuredOutputs.json(
    Map<String, dynamic> schema, {
    String? whitespacePattern,
  }) : this._('json', schema, whitespacePattern: whitespacePattern);

  /// Constrain output to match a regular expression.
  const VLLMStructuredOutputs.regex(String pattern) : this._('regex', pattern);

  /// Constrain output to be exactly one of [choices].
  const VLLMStructuredOutputs.choice(List<String> choices)
    : this._('choice', choices);

  /// Constrain output to a context-free grammar (EBNF).
  const VLLMStructuredOutputs.grammar(String grammar)
    : this._('grammar', grammar);

  /// Constrain output with a structural tag definition.
  const VLLMStructuredOutputs.structuralTag(Map<String, dynamic> tag)
    : this._('structural_tag', tag);

  final String _key;
  final Object _value;

  /// Optional whitespace pattern applied to JSON-constrained output.
  final String? whitespacePattern;

  /// The `structured_outputs` payload as vLLM expects it.
  Map<String, dynamic> toJson() => {
    _key: _value,
    if (whitespacePattern != null) 'whitespace_pattern': whitespacePattern,
  };

  /// Wraps [toJson] in the map shape accepted by
  /// `LLMChatOptions.backendOptions`.
  Map<String, dynamic> toBackendOptions() => {'structured_outputs': toJson()};
}
