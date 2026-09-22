import 'package:llm_core/llm_core.dart';

/// Usage metadata reported by the Gemini Interactions API.
///
/// The Interactions API reports usage with different field names than the
/// legacy `generateContent` API (`promptTokenCount` / `candidatesTokenCount`):
///
/// ```json
/// {
///   "total_tokens": 120,
///   "total_input_tokens": 80,
///   "total_output_tokens": 40,
///   "total_cached_tokens": 0,
///   "total_thought_tokens": 12,
///   "total_tool_use_tokens": 0
/// }
/// ```
class GeminiUsage {
  /// Creates usage metadata.
  const GeminiUsage({
    this.totalTokens = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
    this.thoughtTokens = 0,
    this.toolUseTokens = 0,
  });

  /// Parses an Interactions API `usage` object.
  factory GeminiUsage.fromJson(Map<String, dynamic> json) {
    return GeminiUsage(
      totalTokens: _int(json['total_tokens']),
      inputTokens: _int(json['total_input_tokens']),
      outputTokens: _int(json['total_output_tokens']),
      cachedTokens: _int(json['total_cached_tokens']),
      thoughtTokens: _int(json['total_thought_tokens']),
      toolUseTokens: _int(json['total_tool_use_tokens']),
    );
  }

  /// Total tokens billed for the interaction.
  final int totalTokens;

  /// Tokens consumed by the input.
  final int inputTokens;

  /// Tokens generated as output.
  final int outputTokens;

  /// Tokens served from the context cache.
  final int cachedTokens;

  /// Tokens spent on thinking/reasoning.
  final int thoughtTokens;

  /// Tokens spent on server-side tool use.
  final int toolUseTokens;

  /// Converts to the core [LLMUsage] shape.
  ///
  /// `total_input_tokens` maps to [LLMUsage.promptTokens] and
  /// `total_output_tokens` to [LLMUsage.completionTokens].
  LLMUsage toLLMUsage() {
    return LLMUsage(
      promptTokens: inputTokens,
      completionTokens: outputTokens,
      totalTokens: totalTokens > 0 ? totalTokens : null,
      reasoningTokens: thoughtTokens > 0 ? thoughtTokens : null,
      cachedTokens: cachedTokens > 0 ? cachedTokens : null,
    );
  }

  /// Usage counters kept in `LLMChunk.providerMetadata`.
  ///
  /// `total_cached_tokens` now also has a first-class slot on
  /// [LLMUsage.cachedTokens], but stays here too: removing a key that callers
  /// may already read would be a silent break, and it is the same value from
  /// the same parse rather than a competing source.
  Map<String, dynamic> toProviderMetadata() {
    return <String, dynamic>{
      'total_tokens': totalTokens,
      'total_cached_tokens': cachedTokens,
      'total_thought_tokens': thoughtTokens,
      'total_tool_use_tokens': toolUseTokens,
    };
  }

  static int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
}
