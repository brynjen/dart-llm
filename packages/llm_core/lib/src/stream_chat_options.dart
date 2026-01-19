import 'retry_config.dart';
import 'tool/llm_tool.dart';

/// Options for streaming chat requests.
///
/// This class encapsulates all optional parameters for [LLMChatRepository.streamChat]
/// to reduce parameter proliferation and improve maintainability.
///
/// Example:
/// ```dart
/// final options = StreamChatOptions(
///   think: true,
///   tools: [CalculatorTool()],
///   toolAttempts: 5,
/// );
/// final stream = repo.streamChat('model', messages: messages, options: options);
/// ```
class StreamChatOptions {
  /// Creates streaming chat options.
  ///
  /// [think] - Whether to request thinking/reasoning output (if supported).
  /// [tools] - Optional list of tools the model can use.
  /// [extra] - Additional context to pass to tool executions.
  /// [toolAttempts] - Maximum number of tool calling attempts.
  /// [timeout] - Request timeout (overrides repository default).
  /// [retryConfig] - Retry configuration (overrides repository default).
  const StreamChatOptions({
    this.think = false,
    this.tools = const [],
    this.extra,
    this.toolAttempts,
    this.timeout,
    this.retryConfig,
  });

  /// Whether to request thinking/reasoning output (if supported).
  final bool think;

  /// Optional list of tools the model can use.
  final List<LLMTool> tools;

  /// Additional context to pass to tool executions.
  final dynamic extra;

  /// Maximum number of tool calling attempts.
  ///
  /// If null, uses the repository's default [maxToolAttempts].
  final int? toolAttempts;

  /// Request timeout (overrides repository default).
  ///
  /// If null, uses the repository's default timeout configuration.
  final Duration? timeout;

  /// Retry configuration (overrides repository default).
  ///
  /// If null, uses the repository's default retry configuration.
  final RetryConfig? retryConfig;

  /// Create a copy of these options with some fields changed.
  StreamChatOptions copyWith({
    bool? think,
    List<LLMTool>? tools,
    dynamic extra,
    int? toolAttempts,
    Duration? timeout,
    RetryConfig? retryConfig,
  }) {
    return StreamChatOptions(
      think: think ?? this.think,
      tools: tools ?? this.tools,
      extra: extra ?? this.extra,
      toolAttempts: toolAttempts ?? this.toolAttempts,
      timeout: timeout ?? this.timeout,
      retryConfig: retryConfig ?? this.retryConfig,
    );
  }
}
