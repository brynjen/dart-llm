import 'package:llm_core/src/llm_response_format.dart';
import 'package:llm_core/src/reasoning_effort.dart';
import 'package:llm_core/src/retry_config.dart';
import 'package:llm_core/src/tool/llm_tool.dart';

const Object _unset = Object();

/// Options for chat requests.
///
/// This is the 0.3-facing options type. It keeps provider-specific escape
/// hatches, but models the shared behavior that every backend should honor:
/// generation, reasoning, tools, structured output, timeout, retry, cache, and
/// metrics preferences.
class LLMChatOptions {
  /// Creates chat options.
  const LLMChatOptions({
    bool think = false,
    List<LLMTool>? tools,
    dynamic extra,
    int? toolAttempts,
    bool autoExecuteTools = true,
    Map<String, dynamic>? backendOptions,
    Duration? timeout,
    RetryConfig? retryConfig,
    LLMResponseFormat? responseFormat,
    double? temperature,
    double? topP,
    int? topK,
    int? maxOutputTokens,
    List<String>? stopSequences,
    int? reasoningBudget,
    ReasoningEffort? reasoningEffort,
    bool useCache = false,
    Duration? cacheTtl,
    bool recordMetrics = true,
  }) : this._(
         think: think,
         tools: tools ?? const [],
         extra: extra,
         toolAttempts: toolAttempts,
         autoExecuteTools: autoExecuteTools,
         backendOptions: backendOptions ?? const {},
         timeout: timeout,
         retryConfig: retryConfig,
         responseFormat: responseFormat,
         temperature: temperature,
         topP: topP,
         topK: topK,
         maxOutputTokens: maxOutputTokens,
         stopSequences: stopSequences,
         reasoningBudget: reasoningBudget,
         reasoningEffort: reasoningEffort,
         useCache: useCache,
         cacheTtl: cacheTtl,
         recordMetrics: recordMetrics,
         toolsProvided: tools != null,
         backendOptionsProvided: backendOptions != null,
       );

  const LLMChatOptions._({
    required this.think,
    required this.tools,
    required this.autoExecuteTools,
    required this.backendOptions,
    required this.useCache,
    required this.recordMetrics,
    required bool toolsProvided,
    required bool backendOptionsProvided,
    this.extra,
    this.toolAttempts,
    this.timeout,
    this.retryConfig,
    this.responseFormat,
    this.temperature,
    this.topP,
    this.topK,
    this.maxOutputTokens,
    this.stopSequences,
    this.reasoningBudget,
    this.reasoningEffort,
    this.cacheTtl,
  }) : _toolsProvided = toolsProvided,
       _backendOptionsProvided = backendOptionsProvided;

  /// Whether to request thinking/reasoning output (if supported).
  final bool think;

  /// Optional list of tools the model can use.
  final List<LLMTool> tools;

  /// Whether [tools] was explicitly supplied.
  ///
  /// This lets callers intentionally clear inline tools with
  /// `LLMChatOptions(tools: [])`.
  bool get overridesTools => _toolsProvided;
  final bool _toolsProvided;

  /// Additional context to pass to tool executions.
  final dynamic extra;

  /// Maximum number of tool calling attempts.
  final int? toolAttempts;

  /// Whether tool calls should be executed automatically by the repository.
  final bool autoExecuteTools;

  /// Backend-specific chat options.
  final Map<String, dynamic> backendOptions;

  /// Whether [backendOptions] was explicitly supplied.
  bool get overridesBackendOptions => _backendOptionsProvided;
  final bool _backendOptionsProvided;

  /// Request timeout (overrides repository default).
  final Duration? timeout;

  /// Retry configuration (overrides repository default).
  final RetryConfig? retryConfig;

  /// Structured output format to request from the model.
  final LLMResponseFormat? responseFormat;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus sampling value.
  final double? topP;

  /// Top-K sampling value where supported.
  final int? topK;

  /// Maximum output tokens where supported.
  final int? maxOutputTokens;

  /// Stop sequences where supported.
  final List<String>? stopSequences;

  /// Thinking/reasoning token budget where supported.
  ///
  /// Only honored when [think] is true. When both this and [reasoningEffort]
  /// are set, budget-native backends (vLLM `thinking_token_budget`, legacy
  /// Claude `budget_tokens`) use the budget; effort-native backends derive an
  /// effort level only when [reasoningEffort] is null. Backend-specific
  /// `backendOptions` keys always take precedence over both.
  final int? reasoningBudget;

  /// Portable thinking/reasoning effort level where supported.
  ///
  /// Only honored when [think] is true. Effort-native backends (OpenAI,
  /// Ollama, modern Claude, Gemini) prefer this over [reasoningBudget];
  /// budget-native backends use it only when [reasoningBudget] is null.
  /// Backends clamp to the subset of levels their API accepts. `null` sends
  /// no reasoning parameter (provider default); [ReasoningEffort.none]
  /// actively suppresses thinking where expressible.
  final ReasoningEffort? reasoningEffort;

  /// Whether non-streaming [LLMChatRepository.chatResponse] calls may use cache.
  final bool useCache;

  /// Optional cache TTL for cache writes.
  final Duration? cacheTtl;

  /// Whether metrics should be recorded for this request when configured.
  final bool recordMetrics;

  /// Create a copy of these options with some fields changed.
  ///
  /// Nullable fields use sentinel parameters so passing `null` explicitly clears
  /// the value instead of preserving it.
  LLMChatOptions copyWith({
    bool? think,
    List<LLMTool>? tools,
    Object? extra = _unset,
    Object? toolAttempts = _unset,
    bool? autoExecuteTools,
    Map<String, dynamic>? backendOptions,
    Object? timeout = _unset,
    Object? retryConfig = _unset,
    Object? responseFormat = _unset,
    Object? temperature = _unset,
    Object? topP = _unset,
    Object? topK = _unset,
    Object? maxOutputTokens = _unset,
    Object? stopSequences = _unset,
    Object? reasoningBudget = _unset,
    Object? reasoningEffort = _unset,
    bool? useCache,
    Object? cacheTtl = _unset,
    bool? recordMetrics,
  }) {
    return LLMChatOptions._(
      think: think ?? this.think,
      tools: tools ?? this.tools,
      extra: identical(extra, _unset) ? this.extra : extra,
      toolAttempts: identical(toolAttempts, _unset)
          ? this.toolAttempts
          : toolAttempts as int?,
      autoExecuteTools: autoExecuteTools ?? this.autoExecuteTools,
      backendOptions: backendOptions ?? this.backendOptions,
      timeout: identical(timeout, _unset) ? this.timeout : timeout as Duration?,
      retryConfig: identical(retryConfig, _unset)
          ? this.retryConfig
          : retryConfig as RetryConfig?,
      responseFormat: identical(responseFormat, _unset)
          ? this.responseFormat
          : responseFormat as LLMResponseFormat?,
      temperature: identical(temperature, _unset)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _unset) ? this.topP : topP as double?,
      topK: identical(topK, _unset) ? this.topK : topK as int?,
      maxOutputTokens: identical(maxOutputTokens, _unset)
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      stopSequences: identical(stopSequences, _unset)
          ? this.stopSequences
          : stopSequences as List<String>?,
      reasoningBudget: identical(reasoningBudget, _unset)
          ? this.reasoningBudget
          : reasoningBudget as int?,
      reasoningEffort: identical(reasoningEffort, _unset)
          ? this.reasoningEffort
          : reasoningEffort as ReasoningEffort?,
      useCache: useCache ?? this.useCache,
      cacheTtl: identical(cacheTtl, _unset)
          ? this.cacheTtl
          : cacheTtl as Duration?,
      recordMetrics: recordMetrics ?? this.recordMetrics,
      toolsProvided: tools != null || _toolsProvided,
      backendOptionsProvided: backendOptions != null || _backendOptionsProvided,
    );
  }
}

/// Backward-compatible name for [LLMChatOptions].
///
/// Existing code can keep using `StreamChatOptions` while migrating to the
/// clearer 0.3 name.
class StreamChatOptions extends LLMChatOptions {
  /// Creates chat options.
  const StreamChatOptions({
    super.think,
    super.tools,
    super.extra,
    super.toolAttempts,
    super.autoExecuteTools,
    super.backendOptions,
    super.timeout,
    super.retryConfig,
    super.responseFormat,
    super.temperature,
    super.topP,
    super.topK,
    super.maxOutputTokens,
    super.stopSequences,
    super.reasoningBudget,
    super.reasoningEffort,
    super.useCache,
    super.cacheTtl,
    super.recordMetrics,
  });
}
