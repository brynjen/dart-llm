import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/dto/ollama_embedding_response.dart';
import 'package:llm_ollama/src/http_client_utils.dart';
import 'package:llm_ollama/src/message_converter.dart';
import 'package:llm_ollama/src/ollama_chat_repository_builder.dart';
import 'package:llm_ollama/src/ollama_repository.dart';
import 'package:llm_ollama/src/ollama_stream_converter.dart';

/// Repository for chatting with Ollama.
///
/// Defaults to the standard Ollama base URL of http://localhost:11434.
///
/// **Connection Pooling**: The `http.Client` automatically handles connection
/// pooling. To reuse connections across multiple repository instances, pass
/// the same `httpClient` to each repository.
///
/// Example:
/// ```dart
/// final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');
/// final stream = repo.streamChat('qwen3:0.6b', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class OllamaChatRepository extends LLMChatRepository
    with LLMRepositoryFeatures {
  OllamaChatRepository({
    String? baseUrl,
    int maxToolAttempts = 90,
    RetryConfig? retryConfig,
    TimeoutConfig? timeoutConfig,
    RateLimiter? rateLimiter,
    ResponseCache? responseCache,
    LLMMetrics? metrics,
    http.Client? httpClient,
  }) : this._(
         baseUrl: baseUrl ?? 'http://localhost:11434',
         maxToolAttempts: maxToolAttempts,
         retryConfig: retryConfig,
         timeoutConfig: timeoutConfig,
         rateLimiter: rateLimiter,
         responseCache: responseCache,
         metrics: metrics,
         httpClient:
             httpClient ?? createLLMHttpClient(timeoutConfig: timeoutConfig),
         ownsHttpClient: httpClient == null,
       );

  OllamaChatRepository._({
    required this.baseUrl,
    required this.maxToolAttempts,
    required this.retryConfig,
    required this.timeoutConfig,
    required this.httpClient,
    required this._ownsHttpClient,
    RateLimiter? rateLimiter,
    this.responseCache,
    this.metrics,
  }) : _rateLimiter = rateLimiter?.enabled == true
           ? TokenBucketRateLimiter(rateLimiter!)
           : null,
       _httpHelper = HttpClientHelper(
         httpClient: httpClient,
         timeoutConfig: timeoutConfig,
       ),
       _ollamaRepo = OllamaRepository(baseUrl: baseUrl, httpClient: httpClient);

  /// The base URL of the Ollama server.
  final String baseUrl;

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

  final OllamaRepository _ollamaRepo;

  Uri get uri => Uri.parse('$baseUrl/api/chat');

  /// Create a builder for configuring a new repository instance.
  static OllamaChatRepositoryBuilder builder() {
    return OllamaChatRepositoryBuilder();
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

    if (messages.any((msg) => msg.images != null && msg.images!.isNotEmpty)) {
      if (!(await _ollamaRepo.supportsVision(model))) {
        throw VisionNotSupportedException(
          model,
          'Model $model does not support vision/images',
        );
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': OllamaMessageConverter.messagesToOllamaJson(messages),
      'stream': true,
      'think': _thinkValue(merged),
    };
    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((tool) => tool.toJson)
          .toList(growable: false);
    }
    _applyBackendOptions(body, merged);

    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendStreamingRequest(
          method: 'POST',
          uri: uri,
          headers: {'content-type': 'application/json'},
          body: utf8.encode(json.encode(body)),
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
          final chunkStream = OllamaStreamConverter.toLLMStream(
            response,
            timeoutConfig: timeoutConfig,
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
        case 400:
          final errorBody = await _httpHelper.readErrorBody(response);
          await OllamaErrorHandler.handleBadRequestError(
            errorBody: errorBody,
            model: model,
            thinkRequested: merged.think,
            toolsRequested: merged.tools.isNotEmpty,
          );
          break;
        default:
          final errorBody = await _httpHelper.readErrorBody(response);
          _httpHelper.handleHttpError(
            statusCode: response.statusCode,
            errorBody: errorBody,
            defaultMessage: 'Request failed',
          );
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    // keep_alive and keepAlive are top-level Ollama API fields, not model
    // options. Extract them before building the body so callers (e.g.
    // OllamaPool) can inject keep_alive via the options map.
    final keepAlive = options['keep_alive'] ?? options['keepAlive'];
    final filteredOptions = keepAlive == null
        ? options
        : (Map<String, dynamic>.from(options)
            ..remove('keep_alive')
            ..remove('keepAlive'));

    final body = <String, dynamic>{
      'model': model,
      'input': messages,
      if (filteredOptions.isNotEmpty) 'options': filteredOptions,
      'keep_alive': ?keepAlive,
    };
    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: Uri.parse('$baseUrl/api/embed'),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
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
        return OllamaEmbeddingResponse.fromJson(
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

  /// Resolves the wire value for Ollama's `think` field.
  ///
  /// Ollama accepts a bool or a level string ("low"/"medium"/"high"/"max").
  /// Some models take either (Qwen3, DeepSeek); gpt-oss ignores bools and
  /// requires a level. Ollama has no numeric thinking budget, so
  /// `reasoningBudget` is honored as a level via [reasoningEffortForBudget].
  ///
  /// A bare `think: true` stays a bool so models that reject level strings
  /// keep working; levels are only sent when the caller opted in through
  /// `reasoningEffort` or `reasoningBudget`. A model that rejects the value
  /// errors through the normal error-handler path.
  static Object _thinkValue(MergedOptions merged) {
    final override = merged.backendOptions['think'];
    if (override != null) return override;
    if (!merged.think) return false;
    final effort =
        merged.reasoningEffort ??
        (merged.reasoningBudget != null
            ? reasoningEffortForBudget(merged.reasoningBudget!)
            : null);
    return switch (effort) {
      null => true,
      ReasoningEffort.none => false,
      ReasoningEffort.minimal || ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high || ReasoningEffort.xhigh => 'high',
      ReasoningEffort.max => 'max',
    };
  }

  void _applyBackendOptions(Map<String, dynamic> body, MergedOptions merged) {
    final backendOptions = merged.backendOptions;
    final responseFormat = merged.responseFormat;
    if (responseFormat != null) {
      switch (responseFormat) {
        case JsonFormat():
          body['format'] = 'json';
        case JsonSchemaFormat():
          body['format'] = responseFormat.schema;
      }
    } else if (backendOptions['format'] != null) {
      body['format'] = backendOptions['format'];
    }
    if (backendOptions['options'] != null) {
      body['options'] = Map<String, dynamic>.from(backendOptions['options']);
    }
    final options = Map<String, dynamic>.from(
      body['options'] as Map<String, dynamic>? ?? const {},
    );
    if (merged.temperature != null) {
      options['temperature'] = merged.temperature;
    }
    if (merged.topP != null) {
      options['top_p'] = merged.topP;
    }
    if (merged.topK != null) {
      options['top_k'] = merged.topK;
    }
    if (merged.maxOutputTokens != null) {
      options['num_predict'] = merged.maxOutputTokens;
    }
    if (merged.stopSequences != null) {
      options['stop'] = merged.stopSequences;
    }
    if (backendOptions['temperature'] != null) {
      options['temperature'] = backendOptions['temperature'];
    }
    if (backendOptions['topP'] != null) {
      options['top_p'] = backendOptions['topP'];
    }
    if (backendOptions['topK'] != null) {
      options['top_k'] = backendOptions['topK'];
    }
    if (backendOptions['maxOutputTokens'] != null) {
      options['num_predict'] = backendOptions['maxOutputTokens'];
    }
    if (backendOptions['stopSequences'] != null) {
      options['stop'] = backendOptions['stopSequences'];
    }
    if (options.isNotEmpty) {
      body['options'] = options;
    }
    final keepAlive = backendOptions.containsKey('keep_alive')
        ? backendOptions['keep_alive']
        : backendOptions['keepAlive'];
    if (keepAlive != null) {
      body['keep_alive'] = keepAlive;
    }
  }
}
