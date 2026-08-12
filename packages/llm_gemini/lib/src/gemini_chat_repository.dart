import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_gemini/src/dto/gemini_embedding_response.dart';
import 'package:llm_gemini/src/gemini_chat_repository_builder.dart';
import 'package:llm_gemini/src/gemini_error_handler.dart';
import 'package:llm_gemini/src/gemini_message_converter.dart';
import 'package:llm_gemini/src/gemini_stream_converter.dart';

/// Repository for chatting with Google's Gemini models.
///
/// Chat runs on the Interactions API (`POST /v1beta/interactions`), not the
/// legacy `generateContent` endpoint. Embeddings still use `embedContent` /
/// `batchEmbedContents`.
///
/// The API key is sent in the `x-goog-api-key` header rather than a `key=`
/// query parameter, so it does not leak into request logs, proxies, or crash
/// reports.
///
/// Example:
/// ```dart
/// final repo = GeminiChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('gemini-3.5-flash-lite', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class GeminiChatRepository extends LLMChatRepository
    with LLMRepositoryFeatures {
  GeminiChatRepository({
    required String apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com',
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

  GeminiChatRepository._({
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

  /// The Google API key.
  final String apiKey;

  /// The base URL for the Gemini API.
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

  static const String _apiVersion = 'v1beta';

  /// Request body keys owned by the repository and the generation-config keys
  /// it maps itself; anything else in `backendOptions` is passed through.
  static const Set<String> _handledBackendOptionKeys = {
    'temperature',
    'max_output_tokens',
    'thinking_level',
    'thinking_summaries',
    'generation_config',
    'previous_interaction_id',
  };

  /// The Interactions endpoint used for all chat traffic.
  Uri get interactionsUri => Uri.parse('$baseUrl/$_apiVersion/interactions');

  Uri _embedUri(String model) =>
      Uri.parse('$baseUrl/$_apiVersion/models/$model:embedContent');

  Uri _batchEmbedUri(String model) =>
      Uri.parse('$baseUrl/$_apiVersion/models/$model:batchEmbedContents');

  /// Create a builder for configuring a new repository instance.
  static GeminiChatRepositoryBuilder builder() {
    return GeminiChatRepositoryBuilder();
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

    final body = <String, dynamic>{
      'model': model,
      'input': GeminiMessageConverter.buildStatelessInput(messages),
      'stream': true,
      // Interactions are stored server-side by default (`store: true`), which
      // would duplicate history that `streamChat` already sends in full on
      // every call. `streamChat` is stateless, so storage is declined.
      'store': false,
    };

    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map(GeminiMessageConverter.toolToFunctionSpec)
          .toList(growable: false);
    }

    final responseFormat = _responseFormatValue(merged.responseFormat);
    if (responseFormat != null) body['response_format'] = responseFormat;

    final generationConfig = _buildGenerationConfig(merged);
    if (generationConfig.isNotEmpty) {
      body['generation_config'] = generationConfig;
    }

    // Stateful continuation escape hatch: callers that opt into server-side
    // storage can chain interactions instead of resending history.
    final previousInteractionId =
        merged.backendOptions['previous_interaction_id'];
    if (previousInteractionId != null) {
      body['previous_interaction_id'] = previousInteractionId;
    }

    // Any remaining backend options are passed through at the top level.
    for (final entry in merged.backendOptions.entries) {
      if (!_handledBackendOptionKeys.contains(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendStreamingRequest(
          method: 'POST',
          uri: interactionsUri,
          headers: _headers(accept: 'text/event-stream'),
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
        final chunkStream = GeminiStreamConverter.toLLMStream(
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
        GeminiErrorHandler.handleError(
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
    // For single or multiple texts, use batchEmbedContents if more than one
    if (messages.length == 1) {
      final body = {
        'model': 'models/$model',
        'content': {
          'parts': [
            {'text': messages.first},
          ],
        },
        ...options,
      };
      final response = await RateLimiterUtil.executeWithRateLimit(
        rateLimiter: _rateLimiter,
        operation: () => RetryUtil.executeWithRetry(
          operation: () => _httpHelper.sendNonStreamingRequest(
            method: 'POST',
            uri: _embedUri(model),
            headers: _headers(accept: 'application/json'),
            body: json.encode(body),
          ),
          config: retryConfig,
          isRetryable: (error) =>
              ErrorHandlers.isRetryableError(error, retryConfig),
        ),
      );
      switch (response.statusCode) {
        case 200:
          final embeddingResponse = GeminiEmbeddingResponse.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          );
          return [embeddingResponse.toLLMEmbedding(model)];
        default:
          throw LLMApiException(
            'Error generating embedding',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
      }
    } else {
      return batchEmbed(model: model, messages: messages, options: options);
    }
  }

  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final requests = messages
        .map(
          (text) => {
            'model': 'models/$model',
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        )
        .toList(growable: false);

    final body = <String, dynamic>{'requests': requests, ...options};
    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: _batchEmbedUri(model),
          headers: _headers(accept: 'application/json'),
          body: json.encode(body),
        ),
        config: retryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, retryConfig),
      ),
    );
    switch (response.statusCode) {
      case 200:
        return GeminiBatchEmbeddingResponse.fromJson(
          json.decode(response.body) as Map<String, dynamic>,
        ).toLLMEmbeddings(model);
      default:
        throw LLMApiException(
          'Error generating embeddings',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
    }
  }

  /// Maps a token-oriented [LLMChatOptions.reasoningBudget] onto the
  /// Interactions API's discrete `thinking_level`.
  ///
  /// The Interactions API has no raw thinking-token-budget field, so a budget
  /// cannot be forwarded as-is. These thresholds are a deliberate heuristic —
  /// Google publishes no token-to-level equivalence:
  ///
  /// | `reasoningBudget`   | `thinking_level` |
  /// |---------------------|------------------|
  /// | `null`              | `medium`         |
  /// | `<= 0`              | `minimal`        |
  /// | `< 2048`            | `low`            |
  /// | `< 8192`            | `medium`         |
  /// | `>= 8192`           | `high`           |
  ///
  /// Set `backendOptions['thinking_level']` to bypass the mapping entirely.
  static String thinkingLevelForBudget(int? reasoningBudget) {
    if (reasoningBudget == null) return 'medium';
    if (reasoningBudget <= 0) return 'minimal';
    if (reasoningBudget < 2048) return 'low';
    if (reasoningBudget < 8192) return 'medium';
    return 'high';
  }

  Map<String, String> _headers({required String accept}) {
    return {
      'content-type': 'application/json',
      'accept': accept,
      'x-goog-api-key': apiKey,
    };
  }

  /// Builds the `generation_config` object.
  ///
  /// Only the documented fields are populated: `temperature`,
  /// `max_output_tokens`, `thinking_level`, and `thinking_summaries`. The
  /// Interactions API documents no `top_p`, `top_k`, or `stop_sequences`
  /// fields, so those [LLMChatOptions] values are not sent; pass them through
  /// `backendOptions['generation_config']` if a model turns out to accept them.
  static Map<String, dynamic> _buildGenerationConfig(MergedOptions options) {
    final config = <String, dynamic>{};

    if (options.temperature != null) {
      config['temperature'] = options.temperature;
    }
    if (options.maxOutputTokens != null) {
      config['max_output_tokens'] = options.maxOutputTokens;
    }

    // Thought summaries are the only way thinking text reaches the client.
    config['thinking_summaries'] = options.think ? 'auto' : 'off';
    final explicitLevel = options.backendOptions['thinking_level'];
    if (explicitLevel != null) {
      config['thinking_level'] = explicitLevel;
    } else if (options.think) {
      config['thinking_level'] = thinkingLevelForBudget(
        options.reasoningBudget,
      );
    }

    final extraConfig = options.backendOptions['generation_config'];
    if (extraConfig is Map) {
      config.addAll(Map<String, dynamic>.from(extraConfig));
    }
    for (final key in const [
      'temperature',
      'max_output_tokens',
      'thinking_summaries',
    ]) {
      if (options.backendOptions.containsKey(key)) {
        config[key] = options.backendOptions[key];
      }
    }

    return config;
  }

  /// Builds the `response_format` array for structured output.
  ///
  /// **Inferred shape.** The Interactions contract documents `response_format`
  /// as an array but not its element shape, so entries are modeled on the flat,
  /// `type`-discriminated objects the API uses for `tools`. Standard lowercase
  /// JSON Schema is forwarded unchanged — unlike `generateContent`, whose
  /// `responseSchema` required UPPERCASE type names. If structured output
  /// requests fail with HTTP 400, check this function and
  /// [GeminiMessageConverter.buildStatelessInput].
  static List<Map<String, dynamic>>? _responseFormatValue(
    LLMResponseFormat? format,
  ) {
    if (format == null) return null;
    switch (format) {
      case JsonFormat():
        return [
          <String, dynamic>{'type': 'json_object'},
        ];
      case JsonSchemaFormat(:final name, :final schema):
        return [
          <String, dynamic>{
            'type': 'json_schema',
            'name': name,
            'schema': schema,
          },
        ];
    }
  }
}
