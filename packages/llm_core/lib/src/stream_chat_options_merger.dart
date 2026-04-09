import 'package:llm_core/src/llm_response_format.dart';
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
    StreamChatOptions? options,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
    bool autoExecuteTools = true,
    Map<String, dynamic> backendOptions = const {},
    LLMResponseFormat? responseFormat,
  }) {
    return MergedOptions(
      think: options?.think ?? think,
      tools: (options?.tools.isNotEmpty ?? false) ? options!.tools : tools,
      extra: options?.extra ?? extra,
      toolAttempts: options?.toolAttempts ?? toolAttempts,
      autoExecuteTools: options?.autoExecuteTools ?? autoExecuteTools,
      backendOptions: options?.backendOptions ?? backendOptions,
      responseFormat: options?.responseFormat ?? responseFormat,
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
    this.extra,
    this.toolAttempts,
    this.responseFormat,
  });

  final bool think;
  final List<LLMTool> tools;
  final dynamic extra;
  final int? toolAttempts;
  final bool autoExecuteTools;
  final Map<String, dynamic> backendOptions;
  final LLMResponseFormat? responseFormat;
}
