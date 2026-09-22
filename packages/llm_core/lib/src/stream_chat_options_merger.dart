import 'package:llm_core/src/llm_response_format.dart';
import 'package:llm_core/src/reasoning_effort.dart';
import 'package:llm_core/src/retry_config.dart';
import 'package:llm_core/src/stream_chat_options.dart';
import 'package:llm_core/src/tool/llm_tool.dart';

/// Utility for merging StreamChatOptions with individual parameters.
///
/// Handles the common pattern where options take precedence over individual
/// parameters, with sensible defaults.
class StreamChatOptionsMerger {
  /// Merges options with individual parameters.
  ///
  /// [options] - StreamChatOptions object (takes precedence)
  /// [think] - Individual think parameter
  /// [tools] - Individual tools parameter
  /// [extra] - Individual extra parameter
  /// [toolAttempts] - Individual toolAttempts parameter
  /// [autoExecuteTools] - Individual autoExecuteTools parameter
  /// [backendOptions] - Individual backend options
  ///
  /// Returns a [MergedOptions] object with the effective values.
  static MergedOptions merge({
    LLMChatOptions? options,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
    bool autoExecuteTools = true,
    Map<String, dynamic> backendOptions = const {},
    LLMResponseFormat? responseFormat,
    Duration? timeout,
    RetryConfig? retryConfig,
  }) {
    return MergedOptions(
      think: options?.think ?? think,
      tools: (options?.overridesTools ?? false) ? options!.tools : tools,
      extra: options?.extra ?? extra,
      toolAttempts: options?.toolAttempts ?? toolAttempts,
      autoExecuteTools: options?.autoExecuteTools ?? autoExecuteTools,
      backendOptions: (options?.overridesBackendOptions ?? false)
          ? options!.backendOptions
          : backendOptions,
      responseFormat: options?.responseFormat ?? responseFormat,
      timeout: options?.timeout ?? timeout,
      retryConfig: options?.retryConfig ?? retryConfig,
      temperature: options?.temperature,
      topP: options?.topP,
      topK: options?.topK,
      maxOutputTokens: options?.maxOutputTokens,
      stopSequences: options?.stopSequences,
      reasoningBudget: options?.reasoningBudget,
      reasoningEffort: options?.reasoningEffort,
      useCache: options?.useCache ?? false,
      cacheTtl: options?.cacheTtl,
      recordMetrics: options?.recordMetrics ?? true,
      usagePerChunk: options?.usagePerChunk ?? false,
    );
  }
}

/// Result of merging StreamChatOptions with individual parameters.
class MergedOptions {
  MergedOptions({
    required this.think,
    required this.tools,
    required this.autoExecuteTools,
    required this.backendOptions,
    required this.useCache,
    required this.recordMetrics,
    this.usagePerChunk = false,
    this.extra,
    this.toolAttempts,
    this.responseFormat,
    this.timeout,
    this.retryConfig,
    this.temperature,
    this.topP,
    this.topK,
    this.maxOutputTokens,
    this.stopSequences,
    this.reasoningBudget,
    this.reasoningEffort,
    this.cacheTtl,
  });

  final bool think;
  final List<LLMTool> tools;
  final dynamic extra;
  final int? toolAttempts;
  final bool autoExecuteTools;
  final Map<String, dynamic> backendOptions;
  final LLMResponseFormat? responseFormat;
  final Duration? timeout;
  final RetryConfig? retryConfig;
  final double? temperature;
  final double? topP;
  final int? topK;
  final int? maxOutputTokens;
  final List<String>? stopSequences;
  final int? reasoningBudget;
  final ReasoningEffort? reasoningEffort;
  final bool useCache;
  final Duration? cacheTtl;
  final bool recordMetrics;

  /// Whether the caller asked for usage on every streamed chunk.
  ///
  /// See [LLMChatOptions.usagePerChunk]; honored by `llm_vllm` only.
  final bool usagePerChunk;

  /// Rebuilds an [LLMChatOptions] carrying every option this merge resolved.
  ///
  /// The tool loop re-enters `streamChat` for each round, and each backend used
  /// to reconstruct the child's options by listing fields by hand. Three were
  /// missing from all five copies — `useCache`, `cacheTtl` and `recordMetrics`
  /// — so caching and metrics preferences silently stopped applying from the
  /// second round onward. Worse, the omission was invisible: a field added to
  /// [LLMChatOptions] simply never reached round two, and nothing failed.
  ///
  /// Rebuilding from [MergedOptions], which already mirrors every field, makes
  /// that class of bug impossible: a new option is forwarded the moment it is
  /// added here.
  ///
  /// [tools], [extra] and [toolAttempts] are the round's own values, which
  /// differ from the parent's. [retryConfig] and [backendOptions] override the
  /// merged values for backends that resolve them further — vLLM passes its
  /// *normalized* backend options so aliases are not re-expanded every round.
  LLMChatOptions toChatOptions({
    List<LLMTool>? tools,
    dynamic extra,
    int? toolAttempts,
    RetryConfig? retryConfig,
    Map<String, dynamic>? backendOptions,
  }) {
    return LLMChatOptions(
      think: think,
      tools: tools ?? this.tools,
      extra: extra ?? this.extra,
      toolAttempts: toolAttempts ?? this.toolAttempts,
      autoExecuteTools: autoExecuteTools,
      backendOptions: backendOptions ?? this.backendOptions,
      timeout: timeout,
      retryConfig: retryConfig ?? this.retryConfig,
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
      usagePerChunk: usagePerChunk,
    );
  }
}
