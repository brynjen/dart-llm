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
}
