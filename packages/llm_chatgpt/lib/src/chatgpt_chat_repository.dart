import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_chatgpt/src/chatgpt_chat_repository_builder.dart';
import 'package:llm_chatgpt/src/dto/gpt_embedding_response.dart';
import 'package:llm_chatgpt/src/gpt_model_features.dart';
import 'package:llm_chatgpt/src/gpt_stream_converter.dart';

/// Repository for chatting with OpenAI's ChatGPT.
///
/// Add an API key and it should just work. For a reference of model names,
/// see https://platform.openai.com/docs/models/overview
///
/// **Connection Pooling**: The `http.Client` automatically handles connection
/// pooling. To reuse connections across multiple repository instances, pass
/// the same `httpClient` to each repository.
///
/// Example:
/// ```dart
/// final repo = ChatGPTChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('gpt-4o', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class ChatGPTChatRepository extends LLMChatRepository
    with LLMRepositoryFeatures {
  ChatGPTChatRepository({
    required String apiKey,
    String baseUrl = 'https://api.openai.com',
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

  ChatGPTChatRepository._({
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

  /// The base URL for the OpenAI API.
  final String baseUrl;

  /// The API key for OpenAI.
  final String apiKey;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// The HTTP client helper for making requests.
  final HttpClientHelper _httpHelper;

  final bool _ownsHttpClient;

  final TokenBucketRateLimiter? _rateLimiter;

  /// The maximum number of tool attempts to make for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  @override
  final ResponseCache? responseCache;

  @override
  final LLMMetrics? metrics;

  Uri get uri => Uri.parse('$baseUrl/v1/chat/completions');

  /// Create a builder for configuring a new repository instance.
  static ChatGPTChatRepositoryBuilder builder() {
    return ChatGPTChatRepositoryBuilder();
  }

  @override
  LLMCapabilities capabilitiesForModel(String model) {
    return const LLMCapabilities(
      streaming: true,
      tools: true,
      vision: true,
      structuredOutput: true,
      thinking: true,
      embeddings: true,
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

    final body = {
      'model': model,
      'messages': messages.map((msg) => msg.toJson()).toList(growable: false),
      'stream': true,
    };
    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((tool) => tool.toJson)
          .toList(growable: false);
    }

    _applyGenerationOptions(body, merged, model);
    _applyResponseFormat(body, merged.responseFormat);
    _applyBackendOptions(body, merged.backendOptions);

    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendStreamingRequest(
          method: 'POST',
          uri: uri,
          headers: {
            'content-type': 'application/json',
            'accept': 'text/event-stream',
            'authorization': 'Bearer $apiKey',
          },
          body: utf8.encode(json.encode(body)),
          applyTimeoutToSend: true, // OpenAI applies timeout to send
          timeout: merged.timeout,
        ),
        config: effectiveRetryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, effectiveRetryConfig),
      ),
    );
    try {
      switch (response.statusCode) {
        case 200:
          final chunkStream = GPTStreamConverter.toLLMStream(response);
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
          _httpHelper.handleHttpError(
            statusCode: response.statusCode,
            errorBody: errorBody,
            defaultMessage: 'OpenAI API error',
          );
      }
    } catch (e) {
      rethrow;
    }
  }

  static void _applyGenerationOptions(
    Map<String, dynamic> body,
    MergedOptions options,
    String model,
  ) {
    // Reasoning models reject temperature/top_p with a hard 400.
    if (!gptRejectsSamplingParams(model)) {
      if (options.temperature != null) {
        body['temperature'] = options.temperature;
      }
      if (options.topP != null) body['top_p'] = options.topP;
    }
    if (options.maxOutputTokens != null) {
      body['max_completion_tokens'] = options.maxOutputTokens;
    }
    if (options.stopSequences != null) body['stop'] = options.stopSequences;

    // OpenAI has no exact reasoning-token budget — `reasoning_effort` is the
    // only knob, so `reasoningBudget` is honored as a derived effort level.
    // Reasoning models reason regardless of `think`, so the knobs apply on
    // their own; with neither set, nothing is sent (server default).
    // Conventional models reject the parameter, so it is never sent there.
    final effort =
        options.reasoningEffort ??
        (options.reasoningBudget != null
            ? reasoningEffortForBudget(options.reasoningBudget!)
            : null);
    if (effort != null) {
      final wireValue = gptEffortWireValue(model, effort);
      if (wireValue != null) body['reasoning_effort'] = wireValue;
    }

    // Ask for the usage frame OpenAI otherwise omits when streaming.
    body['stream_options'] = {'include_usage': true};
  }

  static void _applyBackendOptions(
    Map<String, dynamic> body,
    Map<String, dynamic> backendOptions,
  ) {
    for (final entry in backendOptions.entries) {
      body[entry.key] = entry.value;
    }
  }

  /// Applies structured output format to the request body.
  static void _applyResponseFormat(
    Map<String, dynamic> body,
    LLMResponseFormat? format,
  ) {
    if (format == null) return;
    switch (format) {
      case JsonFormat():
        body['response_format'] = {'type': 'json_object'};
      case JsonSchemaFormat():
        body['response_format'] = {
          'type': 'json_schema',
          'json_schema': {
            'name': format.name,
            'strict': format.strict,
            'schema': format.schema,
          },
        };
    }
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final body = {'model': model, 'input': messages};
    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: Uri.parse('$baseUrl/v1/embeddings'),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
            'authorization': 'Bearer $apiKey',
          },
          body: json.encode(body),
        ),
        config: retryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, retryConfig),
      ),
    );
    switch (response.statusCode) {
      case 200: // HttpStatus.ok
        return ChatGPTEmbeddingsResponse.fromJson(
          json.decode(response.body),
        ).toLLMEmbedding;
      default:
        throw LLMApiException(
          'Error generating embedding',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
    }
  }

  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    return embed(model: model, messages: messages, options: options);
  }
}
