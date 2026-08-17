import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_claude/src/claude_chat_repository_builder.dart';
import 'package:llm_claude/src/claude_error_handler.dart';
import 'package:llm_claude/src/claude_message_converter.dart';
import 'package:llm_claude/src/claude_model_features.dart';
import 'package:llm_claude/src/claude_stream_converter.dart';

/// Repository for chatting with Anthropic's Claude models.
///
/// Example:
/// ```dart
/// final repo = ClaudeChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('claude-opus-5', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class ClaudeChatRepository extends LLMChatRepository
    with LLMRepositoryFeatures {
  ClaudeChatRepository({
    required String apiKey,
    String baseUrl = 'https://api.anthropic.com',
    int maxToolAttempts = 90,
    RetryConfig? retryConfig,
    TimeoutConfig? timeoutConfig,
    RateLimiter? rateLimiter,
    ResponseCache? responseCache,
    LLMMetrics? metrics,
    http.Client? httpClient,
  }) : this._(
         apiKey: apiKey,
         baseUrl: baseUrl,
         maxToolAttempts: maxToolAttempts,
         retryConfig: retryConfig,
         timeoutConfig: timeoutConfig,
         rateLimiter: rateLimiter,
         responseCache: responseCache,
         metrics: metrics,
         httpClient: httpClient ?? http.Client(),
         ownsHttpClient: httpClient == null,
       );

  ClaudeChatRepository._({
    required this.apiKey,
    required this.baseUrl,
    required this.maxToolAttempts,
    required this.retryConfig,
    required this.timeoutConfig,
    required this.httpClient,
    required bool ownsHttpClient,
    RateLimiter? rateLimiter,
    this.responseCache,
    this.metrics,
  }) : _ownsHttpClient = ownsHttpClient,
       _rateLimiter = rateLimiter?.enabled == true
           ? TokenBucketRateLimiter(rateLimiter!)
           : null,
       _httpHelper = HttpClientHelper(
         httpClient: httpClient,
         timeoutConfig: timeoutConfig,
       );

  /// The Anthropic API key.
  final String apiKey;

  /// The base URL for the Anthropic API.
  final String baseUrl;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// The HTTP client helper for making requests.
  final HttpClientHelper _httpHelper;

  final bool _ownsHttpClient;

  final TokenBucketRateLimiter? _rateLimiter;

  /// The maximum number of tool attempts for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  @override
  final ResponseCache? responseCache;

  @override
  final LLMMetrics? metrics;

  static const String _anthropicVersion = '2023-06-01';
  static const int _defaultMaxTokens = 4096;

  /// Fallback thinking budget for models that still require `budget_tokens`.
  static const int _defaultThinkingBudget = 2048;

  Uri get _messagesUri => Uri.parse('$baseUrl/v1/messages');

  /// Create a builder for configuring a new repository instance.
  static ClaudeChatRepositoryBuilder builder() {
    return ClaudeChatRepositoryBuilder();
  }

  @override
  LLMCapabilities capabilitiesForModel(String model) {
    return const LLMCapabilities(
      streaming: true,
      tools: true,
      vision: true,
      structuredOutput: true,
      thinking: true,
    );
  }

  /// Releases owned resources.
  void close() {
    _rateLimiter?.dispose();
    if (_ownsHttpClient) httpClient.close();
  }

  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
    bool think = false,
    LLMChatOptions? options,
  }) async* {
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    final merged = StreamChatOptionsMerger.merge(
      options: options,
      think: think,
      tools: tools,
      extra: extra,
      toolAttempts: toolAttempts,
      retryConfig: retryConfig,
    );
    final effectiveRetryConfig = merged.retryConfig ?? retryConfig;

    final converted = ClaudeMessageConverter.convert(messages);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': merged.backendOptions['max_tokens'] ?? _defaultMaxTokens,
      'messages': converted.messages,
      'stream': true,
    };

    _applyGenerationOptions(body, merged, model);

    if (converted.system != null) {
      body['system'] = converted.system;
    }

    if (merged.responseFormat != null) {
      if (claudeSupportsStructuredOutputs(model)) {
        // Native structured outputs. Constrains decoding rather than asking
        // the model nicely, so the response is guaranteed to parse.
        _applyStructuredOutputs(body, merged.responseFormat!);
      } else {
        // Older models have no output_config — fall back to instructing the
        // model through the system prompt.
        final instruction = _buildSchemaInstruction(merged.responseFormat!);
        final existing = body['system'] as String?;
        body['system'] = existing != null
            ? '$existing\n\n$instruction'
            : instruction;
      }
    }

    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((t) => _toolToClaudeFormat(t))
          .toList(growable: false);
      final toolChoice = merged.backendOptions['tool_choice'];
      if (toolChoice != null) {
        body['tool_choice'] = toolChoice is String
            ? _toolChoiceFromString(toolChoice)
            : toolChoice;
      }
    }

    _applyThinking(body, merged, model);

    // Merge any additional backend options. Keys already consumed above are
    // skipped so the raw value does not overwrite the converted one.
    const handledKeys = {'max_tokens', 'thinking_budget', 'tool_choice'};
    for (final entry in merged.backendOptions.entries) {
      if (!handledKeys.contains(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendStreamingRequest(
          method: 'POST',
          uri: _messagesUri,
          headers: {
            'content-type': 'application/json',
            'accept': 'text/event-stream',
            'x-api-key': apiKey,
            'anthropic-version': _anthropicVersion,
          },
          body: utf8.encode(json.encode(body)),
          timeout: merged.timeout,
        ),
        config: effectiveRetryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, effectiveRetryConfig),
      ),
    );

    switch (response.statusCode) {
      case 200:
        final chunkStream = ClaudeStreamConverter.toLLMStream(
          response,
          model: model,
        );
        if (merged.tools.isNotEmpty && merged.autoExecuteTools) {
          final executor = StreamToolExecutor(
            tools: merged.tools,
            extra: merged.extra,
            maxToolAttempts: merged.toolAttempts ?? maxToolAttempts,
            streamChatCallback:
                (
                  String model,
                  List<LLMMessage> messages,
                  List<LLMTool> tools,
                  dynamic extra,
                  int toolAttempts,
                ) => streamChat(
                  model,
                  messages: messages,
                  tools: tools,
                  extra: extra,
                  options: LLMChatOptions(
                    think: merged.think,
                    tools: tools,
                    extra: extra,
                    toolAttempts: toolAttempts,
                    autoExecuteTools: merged.autoExecuteTools,
                    backendOptions: merged.backendOptions,
                    timeout: merged.timeout,
                    retryConfig: effectiveRetryConfig,
                    responseFormat: merged.responseFormat,
                    temperature: merged.temperature,
                    topP: merged.topP,
                    topK: merged.topK,
                    maxOutputTokens: merged.maxOutputTokens,
                    stopSequences: merged.stopSequences,
                    reasoningBudget: merged.reasoningBudget,
                    reasoningEffort: merged.reasoningEffort,
                  ),
                ),
          );
          yield* executor.executeTools(
            chunkStream: chunkStream,
            model: model,
            initialMessages: messages,
            toolAttempts: merged.toolAttempts ?? maxToolAttempts,
          );
        } else {
          yield* chunkStream;
        }
      default:
        final errorBody = await _httpHelper.readErrorBody(response);
        ClaudeErrorHandler.handleError(
          statusCode: response.statusCode,
          errorBody: errorBody,
        );
    }
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    throw UnsupportedError(
      'The Anthropic Claude API does not support embeddings. '
      'Consider using a dedicated embedding model or service.',
    );
  }

  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    throw UnsupportedError(
      'The Anthropic Claude API does not support embeddings. '
      'Consider using a dedicated embedding model or service.',
    );
  }

  /// Builds a system-message instruction for structured output.
  ///
  /// Claude has no native response_format API, so the constraint is injected
  /// into the system field and appended after any user-defined system content.
  static String _buildSchemaInstruction(LLMResponseFormat format) =>
      switch (format) {
        JsonFormat() =>
          'Respond with valid JSON only. '
              'Do not include any explanation or text outside the JSON.',
        JsonSchemaFormat() =>
          'Respond with valid JSON only, conforming exactly to the following '
              'JSON Schema. Do not include any explanation or text outside the '
              'JSON.\n\nSchema name: ${format.name}\nSchema:\n'
              '${json.encode(format.schema)}',
      };

  /// Applies native structured outputs via `output_config.format`.
  static void _applyStructuredOutputs(
    Map<String, dynamic> body,
    LLMResponseFormat format,
  ) {
    final outputConfig = <String, dynamic>{
      ...?body['output_config'] as Map<String, dynamic>?,
    };
    switch (format) {
      case JsonFormat():
        // No schema to enforce; a bare JSON instruction is the closest
        // equivalent the API offers.
        final existing = body['system'] as String?;
        final instruction = _buildSchemaInstruction(format);
        body['system'] = existing != null
            ? '$existing\n\n$instruction'
            : instruction;
        return;
      case JsonSchemaFormat():
        outputConfig['format'] = {
          'type': 'json_schema',
          'schema': format.schema,
        };
    }
    body['output_config'] = outputConfig;
  }

  static void _applyGenerationOptions(
    Map<String, dynamic> body,
    MergedOptions options,
    String model,
  ) {
    // temperature / top_p / top_k are rejected with a 400 on Opus 4.7+,
    // Sonnet 5, Fable 5 and Mythos 5. Sending them unconditionally would make
    // every request to a current model fail, so they are dropped for those
    // models — steer behavior through the prompt instead.
    if (!claudeRejectsSamplingParams(model)) {
      if (options.temperature != null) {
        body['temperature'] = options.temperature;
      }
      if (options.topP != null) body['top_p'] = options.topP;
      if (options.topK != null) body['top_k'] = options.topK;
    }
    if (options.maxOutputTokens != null) {
      body['max_tokens'] = options.maxOutputTokens;
    }
    if (options.stopSequences != null) {
      body['stop_sequences'] = options.stopSequences;
    }
  }

  /// Applies the thinking configuration appropriate to [model].
  ///
  /// Adaptive thinking replaced the fixed token budget: `budget_tokens` is a
  /// `400` on Opus 4.7+, Sonnet 5, Fable 5 and Mythos 5, while `adaptive` is a
  /// `400` on models older than Opus 4.6. A [MergedOptions.reasoningBudget] is
  /// translated to an `output_config.effort` level on models that dropped
  /// budgets, so the caller's intent survives instead of being ignored.
  static void _applyThinking(
    Map<String, dynamic> body,
    MergedOptions options,
    String model,
  ) {
    if (!options.think) return;

    final budget =
        options.reasoningBudget ??
        options.backendOptions['thinking_budget'] as int?;

    if (claudeSupportsAdaptiveThinking(model)) {
      body['thinking'] = {
        'type': 'adaptive',
        // The API default is "omitted", which streams thinking blocks whose
        // text is empty — chunk.message.thinking would always be blank. Ask
        // for summaries so reasoning is actually observable.
        'display': 'summarized',
      };
      // Effort-native path: an explicit reasoningEffort wins over a
      // budget-derived level.
      final effort = options.reasoningEffort != null
          ? claudeEffortWireValue(options.reasoningEffort!)
          : (budget != null ? claudeEffortForBudget(budget) : null);
      if (effort != null) {
        final outputConfig = <String, dynamic>{
          ...?body['output_config'] as Map<String, dynamic>?,
        };
        outputConfig['effort'] = effort;
        body['output_config'] = outputConfig;
      }
      return;
    }

    // Legacy models: budget_tokens is required, and the API rejects a budget
    // that is not strictly less than max_tokens. The previous default paired a
    // 10000-token budget with a 4096-token max_tokens, which was a guaranteed
    // 400 on every `think: true` request that did not set max_tokens. This is
    // the budget-native path: an explicit budget wins over an effort-derived
    // one.
    final maxTokens = body['max_tokens'] as int? ?? _defaultMaxTokens;
    final requested =
        budget ??
        (options.reasoningEffort != null
            ? claudeBudgetForEffort(options.reasoningEffort!)
            : _defaultThinkingBudget);
    final effective = requested < maxTokens ? requested : maxTokens - 1;
    body['thinking'] = {'type': 'enabled', 'budget_tokens': effective};
  }

  /// Accepts OpenAI-style `tool_choice` shorthands and converts them to the
  /// object form the Messages API expects.
  static Map<String, dynamic> _toolChoiceFromString(String choice) =>
      switch (choice) {
        'auto' => {'type': 'auto'},
        'any' || 'required' => {'type': 'any'},
        'none' => {'type': 'none'},
        _ => {'type': 'tool', 'name': choice},
      };

  /// Converts an [LLMTool] to Claude's tool format.
  static Map<String, dynamic> _toolToClaudeFormat(LLMTool tool) {
    // LLMTool.toJson produces OpenAI format; adapt to Claude format
    final openAiFormat = tool.toJson;
    final function = openAiFormat['function'] as Map<String, dynamic>? ?? {};
    return {
      'name': function['name'] ?? tool.name,
      'description': function['description'] ?? tool.description,
      'input_schema':
          function['parameters'] ?? {'type': 'object', 'properties': {}},
    };
  }
}
