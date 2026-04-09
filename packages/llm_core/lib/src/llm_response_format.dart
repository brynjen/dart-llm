/// Structured output format for LLM responses.
///
/// Use [JsonFormat] to request JSON output without enforcing a schema, or
/// [JsonSchemaFormat] to require the model to produce JSON conforming to
/// a specific JSON Schema object.
///
/// Both subtypes are `const`-constructible:
/// ```dart
/// const StreamChatOptions(responseFormat: JsonFormat())
///
/// const StreamChatOptions(
///   responseFormat: JsonSchemaFormat(
///     name: 'User',
///     schema: {
///       'type': 'object',
///       'properties': {
///         'name': {'type': 'string'},
///         'age':  {'type': 'integer'},
///       },
///       'required': ['name', 'age'],
///     },
///   ),
/// )
/// ```
///
/// ### Backend behaviour
///
/// | Backend   | JsonFormat                          | JsonSchemaFormat                          |
/// |-----------|-------------------------------------|-------------------------------------------|
/// | ChatGPT   | `response_format.type=json_object`  | `response_format.type=json_schema`        |
/// | Gemini    | `generationConfig.responseMimeType` | + `generationConfig.responseSchema`       |
/// | Ollama    | `format="json"`                     | `format={schema}` (model must support it) |
/// | Claude    | System-message injection            | System-message injection with schema      |
/// | llamacpp  | System-message injection            | System-message injection with schema      |
///
/// ### Gemini type names
///
/// Gemini's `responseSchema` uses uppercase type names (`"STRING"`, `"OBJECT"`,
/// `"ARRAY"`, etc.) rather than the lowercase used in standard JSON Schema.
/// When targeting Gemini with [JsonSchemaFormat], provide a schema using
/// Gemini's conventions.
sealed class LLMResponseFormat {
  const LLMResponseFormat();
}

/// Requests JSON output with no schema enforcement.
///
/// The model is instructed to produce valid JSON but the structure is
/// unconstrained. Supported natively by ChatGPT, Gemini, and Ollama; injected
/// via system message for Claude and llamacpp.
final class JsonFormat extends LLMResponseFormat {
  const JsonFormat();
}

/// Requests JSON output conforming to a specific JSON Schema.
///
/// [name] is a human-readable identifier for the schema (required by the
/// ChatGPT `json_schema` response format; used in injected instructions for
/// Claude and llamacpp).
///
/// [schema] is a `Map<String, dynamic>` representing the JSON Schema the
/// model output must conform to.
///
/// [strict] controls whether the model is penalised for deviating from the
/// schema (ChatGPT only; defaults to `true`).
final class JsonSchemaFormat extends LLMResponseFormat {
  const JsonSchemaFormat({
    required this.name,
    required this.schema,
    this.strict = true,
  });

  /// A human-readable name for the schema.
  final String name;

  /// The JSON Schema the model output must conform to.
  final Map<String, dynamic> schema;

  /// Whether the model should strictly adhere to the schema (ChatGPT only).
  final bool strict;
}
