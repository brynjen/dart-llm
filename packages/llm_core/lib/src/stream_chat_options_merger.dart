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
  ///
  /// Returns a [MergedOptions] object with the effective values.
  static MergedOptions merge({
    StreamChatOptions? options,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
  }) {
    return MergedOptions(
      think: options?.think ?? think,
      tools: (options?.tools.isNotEmpty ?? false) ? options!.tools : tools,
      extra: options?.extra ?? extra,
      toolAttempts: options?.toolAttempts ?? toolAttempts,
    );
  }
}

/// Result of merging StreamChatOptions with individual parameters.
class MergedOptions {
  MergedOptions({
    required this.think,
    required this.tools,
    this.extra,
    this.toolAttempts,
  });

  final bool think;
  final List<LLMTool> tools;
  final dynamic extra;
  final int? toolAttempts;
}
