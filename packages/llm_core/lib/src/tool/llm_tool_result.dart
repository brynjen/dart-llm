import 'package:llm_core/src/llm_message.dart';

/// The outcome of running an [LLMTool], with the structure a caller needs and
/// the text the model sees.
///
/// `LLMTool.execute` returns `dynamic`, so a tool that knows more than "here is
/// a string" had nowhere to put it: whether the run succeeded, what the exit
/// code was, anything an application wanted to render. Callers resorted to
/// sniffing the returned object, and this package resorted to *reading the
/// error message* — `ClaudeMessageConverter` decided whether to set Anthropic's
/// `is_error` by matching the literal text `'Tool <name> failed:'`.
///
/// Returning one of these from `execute` replaces both. [isError] is the
/// authoritative failure signal, [metadata] carries the structured outcome, and
/// [content] is what goes to the model.
///
/// ```dart
/// @override
/// Future<LLMToolResult> execute(Map<String, dynamic> args, {extra}) async {
///   final run = await Process.run('ls', [args['path'] as String]);
///   return LLMToolResult(
///     content: run.exitCode == 0 ? run.stdout as String : run.stderr as String,
///     isError: run.exitCode != 0,
///     metadata: {'exit_code': run.exitCode},
///   );
/// }
/// ```
///
/// `execute` keeps its `dynamic` return type, so returning a plain `String` —
/// or anything else — works exactly as before; [LLMToolResult.from] normalizes
/// it.
///
/// The shape follows the specifications rather than inventing one: MCP's
/// `CallToolResult` is `content` + `isError` + `structuredContent`, the Vercel
/// AI SDK's tool result part carries `isError`, and LangChain's `ToolMessage`
/// carries `status` plus an `artifact` the model never sees. `isError` is also
/// Anthropic's own field name on a `tool_result` block.
class LLMToolResult {
  /// Creates a tool result.
  const LLMToolResult({
    required this.content,
    this.contentParts = const [],
    this.isError = false,
    this.metadata = const {},
  });

  /// Creates a failed result.
  const LLMToolResult.failure(
    this.content, {
    this.contentParts = const [],
    this.metadata = const {},
  }) : isError = true;

  /// Normalizes whatever `LLMTool.execute` returned into a result.
  ///
  /// An [LLMToolResult] passes through. Everything else keeps the exact
  /// behavior callers had before this type existed, including the wording of
  /// the null placeholder, so an existing tool sees no change: `null` becomes
  /// `'Tool <name> returned null'`, a `String` is used as-is, and anything else
  /// is stringified.
  factory LLMToolResult.from(Object? value, {required String toolName}) {
    if (value is LLMToolResult) return value;
    if (value == null) {
      return LLMToolResult(content: 'Tool $toolName returned null');
    }
    if (value is String) return LLMToolResult(content: value);
    return LLMToolResult(content: value.toString());
  }

  /// The result as the model will read it.
  ///
  /// Required and non-null because every provider needs text here: a tool
  /// message's `content` on OpenAI-compatible APIs, a `tool_result` block's
  /// string content on Anthropic, a `function_result` response on Gemini.
  final String content;

  /// The result as richer content, for providers that accept more than text.
  ///
  /// Anthropic's `tool_result.content` takes a list of `text`, `image`,
  /// `document` or `search_result` blocks, so a tool that returns a screenshot
  /// or a chart can hand back the image itself instead of a description of it.
  ///
  /// **Reuses the existing [LLMMessageContent] variants** — there is no
  /// tool-specific content type — so an image result is an [LLMImageContent]
  /// exactly as it would be in a user message.
  ///
  /// Degrades where a provider cannot carry it: OpenAI-compatible tool
  /// messages, Ollama and Gemini are text-only, so they send [content] and drop
  /// the parts. Always set [content] to a usable text form, even when this is
  /// populated, or those providers get nothing.
  final List<LLMMessageContent> contentParts;

  /// Whether the run failed.
  ///
  /// Set on a thrown exception and on a call that was never run because its
  /// arguments did not decode. This is the only field with a wire consequence:
  /// Anthropic's `tool_result` block carries `is_error`, and without it the
  /// model reads a failure message as data.
  final bool isError;

  /// Structured detail about the run, for the application.
  ///
  /// **Never sent to the model** — this is LangChain's `artifact`: exit codes,
  /// durations, byte counts, anything a UI or a retry policy wants. A tool that
  /// wants the *model* to see structure encodes it into [content] as well.
  final Map<String, dynamic> metadata;

  /// Returns a copy with the given fields replaced.
  LLMToolResult copyWith({
    String? content,
    List<LLMMessageContent>? contentParts,
    bool? isError,
    Map<String, dynamic>? metadata,
  }) => LLMToolResult(
    content: content ?? this.content,
    contentParts: contentParts ?? this.contentParts,
    isError: isError ?? this.isError,
    metadata: metadata ?? this.metadata,
  );

  @override
  String toString() =>
      'LLMToolResult(isError: $isError, content: $content'
      '${metadata.isEmpty ? '' : ', metadata: $metadata'})';
}
