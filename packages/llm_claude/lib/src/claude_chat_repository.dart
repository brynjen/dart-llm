import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_claude/src/claude_chat_repository_builder.dart';
import 'package:llm_claude/src/claude_error_handler.dart';
import 'package:llm_claude/src/claude_message_converter.dart';
import 'package:llm_claude/src/claude_stream_converter.dart';

/// Repository for chatting with Anthropic's Claude models.
///
/// Example:
/// ```dart
/// final repo = ClaudeChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('claude-opus-4-6', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class ClaudeChatRepository extends LLMChatRepository {
  ClaudeChatRepository({
    required this.apiKey,
    this.baseUrl = 'https://api.anthropic.com',
    this.maxToolAttempts = 90,
    this.retryConfig,
    this.timeoutConfig,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _httpHelper = HttpClientHelper(
         httpClient: httpClient ?? http.Client(),
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

  /// The maximum number of tool attempts for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  static const String _anthropicVersion = '2023-06-01';
  static const int _defaultMaxTokens = 4096;

  Uri get _messagesUri => Uri.parse('$baseUrl/v1/messages');

  /// Create a builder for configuring a new repository instance.
  static ClaudeChatRepositoryBuilder builder() {
    return ClaudeChatRepositoryBuilder();
  }

  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
    bool think = false,
    StreamChatOptions? options,
  }) async* {
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    final merged = StreamChatOptionsMerger.merge(
      options: options,
      think: think,
      tools: tools,
      extra: extra,
      toolAttempts: toolAttempts,
    );

    final converted = ClaudeMessageConverter.convert(messages);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': merged.backendOptions['max_tokens'] ?? _defaultMaxTokens,
      'messages': converted.messages,
      'stream': true,
    };

    if (converted.system != null) {
      body['system'] = converted.system;
    }

    // Inject structured output instruction into the system field
    if (merged.responseFormat != null) {
      final instruction = _buildSchemaInstruction(merged.responseFormat!);
      final existing = body['system'] as String?;
      body['system'] =
          existing != null ? '$existing\n\n$instruction' : instruction;
    }

    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((t) => _toolToClaudeFormat(t))
          .toList(growable: false);
    }

    if (merged.think) {
      final budget = merged.backendOptions['thinking_budget'] ?? 10000;
      body['thinking'] = {'type': 'enabled', 'budget_tokens': budget};
    }

    // Merge any additional backend options (excluding handled keys)
    for (final entry in merged.backendOptions.entries) {
      if (!const {'max_tokens', 'thinking_budget'}.contains(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await RetryUtil.executeWithRetry(
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
      ),
      config: retryConfig,
      isRetryable: (error) =>
          ErrorHandlers.isRetryableError(error, retryConfig),
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
                  options: StreamChatOptions(
                    think: merged.think,
                    tools: tools,
                    extra: extra,
                    toolAttempts: toolAttempts,
                    autoExecuteTools: merged.autoExecuteTools,
                    backendOptions: merged.backendOptions,
                    responseFormat: merged.responseFormat,
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
