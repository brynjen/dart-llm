import 'package:llm_core/src/llm_response_format.dart';
import 'package:llm_core/src/retry_config.dart';
import 'package:llm_core/src/tool/llm_tool.dart';

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
  /// [autoExecuteTools] - Whether tool calls should be executed automatically.
  /// [backendOptions] - Backend-specific chat options.
  /// [timeout] - Request timeout (overrides repository default).
  /// [retryConfig] - Retry configuration (overrides repository default).
  /// [responseFormat] - Structured output format to request from the model.
  const StreamChatOptions({
    this.think = false,
    this.tools = const [],
    this.extra,
    this.toolAttempts,
    this.autoExecuteTools = true,
    this.backendOptions = const {},
    this.timeout,
    this.retryConfig,
    this.responseFormat,
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

  /// Whether tool calls should be executed automatically by the repository.
  ///
  /// Defaults to `true` for backward compatibility.
  final bool autoExecuteTools;

  /// Backend-specific chat options.
  ///
  /// This is useful for provider-specific request fields that are not yet
  /// modeled as first-class parameters in the core interface.
  final Map<String, dynamic> backendOptions;

  /// Request timeout (overrides repository default).
  ///
  /// If null, uses the repository's default timeout configuration.
  final Duration? timeout;

  /// Retry configuration (overrides repository default).
  ///
  /// If null, uses the repository's default retry configuration.
  final RetryConfig? retryConfig;

  /// Structured output format to request from the model.
  ///
  /// When set, instructs the model to produce JSON output. Use [JsonFormat]
  /// for unconstrained JSON, or [JsonSchemaFormat] to enforce a specific schema.
  ///
  /// If null, no structured output is requested (default behaviour).
  final LLMResponseFormat? responseFormat;

  /// Create a copy of these options with some fields changed.
  StreamChatOptions copyWith({
    bool? think,
    List<LLMTool>? tools,
    dynamic extra,
    int? toolAttempts,
    bool? autoExecuteTools,
    Map<String, dynamic>? backendOptions,
    Duration? timeout,
    RetryConfig? retryConfig,
    LLMResponseFormat? responseFormat,
  }) {
    return StreamChatOptions(
      think: think ?? this.think,
      tools: tools ?? this.tools,
      extra: extra ?? this.extra,
      toolAttempts: toolAttempts ?? this.toolAttempts,
      autoExecuteTools: autoExecuteTools ?? this.autoExecuteTools,
      backendOptions: backendOptions ?? this.backendOptions,
      timeout: timeout ?? this.timeout,
      retryConfig: retryConfig ?? this.retryConfig,
      responseFormat: responseFormat ?? this.responseFormat,
    );
  }
}
