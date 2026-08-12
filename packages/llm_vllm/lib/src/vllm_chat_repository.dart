import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/dto/vllm_embedding_response.dart';
import 'package:llm_vllm/src/http_client_utils.dart';
import 'package:llm_vllm/src/vllm_base_url.dart';
import 'package:llm_vllm/src/vllm_chat_repository_builder.dart';
import 'package:llm_vllm/src/vllm_params.dart';
import 'package:llm_vllm/src/vllm_stream_converter.dart';

/// Repository for chatting with a vLLM OpenAI-compatible server.
///
/// Defaults to the common vLLM serving URL of `http://localhost:8000`.
///
/// ## Retry scope
///
/// Retries cover **establishing** the request. Once the server has begun
/// streaming, a dropped connection ends the stream with an error and is not
/// retried: the tokens already emitted have been handed to the caller, and
/// re-sending would restart generation from the beginning and duplicate them.
///
/// For long generations where a mid-stream drop is costly, accumulate chunks
/// on your side and re-issue the request with the partial output appended to
/// the conversation, rather than expecting transparent resumption.
class VLLMChatRepository extends LLMChatRepository with LLMRepositoryFeatures {
  VLLMChatRepository({
    String? baseUrl,
    String? apiKey,
    int maxToolAttempts = 90,
    RetryConfig? retryConfig,
    TimeoutConfig? timeoutConfig,
    RateLimiter? rateLimiter,
    ResponseCache? responseCache,
    LLMMetrics? metrics,
    http.Client? httpClient,
    Set<String>? supportedParams,
    LLMCapabilities? capabilities,
  }) : this._(
         baseUrl: baseUrl ?? 'http://localhost:8000',
         supportedParams: supportedParams,
         capabilities: capabilities,
         apiKey: apiKey,
         maxToolAttempts: maxToolAttempts,
         retryConfig: retryConfig,
         timeoutConfig: timeoutConfig,
         rateLimiter: rateLimiter,
         responseCache: responseCache,
         metrics: metrics,
         httpClient: httpClient ?? http.Client(),
         ownsHttpClient: httpClient == null,
       );

  VLLMChatRepository._({
    required this.baseUrl,
    required this.apiKey,
    required this.maxToolAttempts,
    required this.retryConfig,
    required this.timeoutConfig,
    required this.httpClient,
    required bool ownsHttpClient,
    this.supportedParams,
    this.capabilities,
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

  /// The base URL of the vLLM server.
  final String baseUrl;

  /// Optional API key for vLLM servers started with `--api-key`.
  final String? apiKey;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  final HttpClientHelper _httpHelper;
  final bool _ownsHttpClient;
  final TokenBucketRateLimiter? _rateLimiter;

  /// The maximum number of tool attempts to make for a single request.
  final int maxToolAttempts;

  /// Deployment capabilities, overriding [backendCapabilities] when known.
  ///
  /// Set this from `VLLMRepository.resolveCapabilities()` so
  /// [capabilitiesForModel] reports what the connected server actually offers
  /// rather than what the backend implements.
  final LLMCapabilities? capabilities;

  /// Request parameters this server accepts, used to validate
  /// `LLMChatOptions.backendOptions`.
  ///
  /// Defaults to [knownVllmChatParams], a snapshot of vLLM's schema. Set it
  /// from `VLLMRepository.fetchSupportedParams()` to validate against the
  /// running server instead, which additionally catches parameters added or
  /// removed in that server's vLLM version.
  final Set<String>? supportedParams;

  /// Retry configuration for transient failures.
  ///
  /// Defaults to [defaultRetryConfig] rather than to no retries: a vLLM server
  /// answers `503` while it is still loading weights, which is the most common
  /// transient failure against a freshly started instance. Pass
  /// `RetryConfig(maxAttempts: 0)` to opt out.
  final RetryConfig? retryConfig;

  /// Retry policy applied when none is configured.
  ///
  /// Three attempts with exponential backoff on `429` and `5xx`.
  static const RetryConfig defaultRetryConfig = RetryConfig();

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  @override
  final ResponseCache? responseCache;

  @override
  final LLMMetrics? metrics;

  Uri get uri => vllmEndpoint(baseUrl, 'chat/completions');

  /// Create a builder for configuring a new repository instance.
  static VLLMChatRepositoryBuilder builder() {
    return VLLMChatRepositoryBuilder();
  }

  /// What this backend is capable of, **not** what the connected deployment
  /// currently offers.
  ///
  /// vLLM serves one model per process, and several of these depend on how the
  /// server was started or on which model it loaded:
  ///
  /// - `tools` needs `--enable-auto-tool-choice` and `--tool-call-parser`
  /// - `thinking` needs a model whose chat template supports it
  /// - `vision` needs a multimodal model
  /// - `embeddings` needs an embedding model
  ///
  /// So a `true` here means "`llm_vllm` implements this", not "this server
  /// will accept it". For the connected deployment, use
  /// `VLLMRepository.resolveCapabilities()`, which probes the server, or pass
  /// a known-correct [LLMCapabilities] as the `capabilities` constructor
  /// argument — that value is returned verbatim when set.
  @override
  LLMCapabilities capabilitiesForModel(String model) =>
      capabilities ?? backendCapabilities;

  /// Capabilities `llm_vllm` implements, before deployment constraints.
  static const LLMCapabilities backendCapabilities = LLMCapabilities(
    streaming: true,
    tools: true,
    vision: true,
    structuredOutput: true,
    thinking: true,
    embeddings: true,
  );

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
    final effectiveRetryConfig =
        merged.retryConfig ?? retryConfig ?? defaultRetryConfig;

    final body = <String, dynamic>{
      'model': model,
      'messages': _mergeConsecutiveSystemMessages(
        messages,
      ).map((msg) => msg.toJson()).toList(growable: false),
      'stream': true,
      'stream_options': {'include_usage': true},
    };
    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((tool) => tool.toJson)
          .toList(growable: false);
      // `tool_choice` is OpenAI-compatible on vLLM. Note that both "auto" and
      // "required" need the server to be started with --tool-call-parser;
      // without it vLLM rejects the request rather than ignoring the field.
      final toolChoice = merged.backendOptions['tool_choice'];
      if (toolChoice != null) {
        body['tool_choice'] =
            toolChoice is String && !_openAiToolChoiceModes.contains(toolChoice)
            ? {
                'type': 'function',
                'function': {'name': toolChoice},
              }
            : toolChoice;
      }
    }

    _validateBackendOptions(
      merged.backendOptions,
      knownParams: supportedParams,
    );
    _applyGenerationOptions(body, merged);
    _applyBackendOptions(body, merged.backendOptions);
    _applyResponseFormat(body, merged.responseFormat);

    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () async {
          final res = await _httpHelper.sendStreamingRequest(
            method: 'POST',
            uri: uri,
            headers: _headers(accept: 'text/event-stream'),
            body: utf8.encode(json.encode(body)),
            applyTimeoutToSend: true,
            timeout: merged.timeout,
          );
          // A non-2xx arrives as a *returned* response, not an exception. The
          // retry wrapper only sees thrown errors, so a retryable status has
          // to be raised here — otherwise RetryConfig.retryableStatusCodes
          // never applies to streaming requests and a 503 from a server that
          // is still loading weights fails on the first attempt.
          //
          // Non-retryable statuses are returned untouched so the switch below
          // can map them to the specific exception types.
          if (effectiveRetryConfig.shouldRetryForStatusCode(res.statusCode)) {
            throw LLMApiException(
              'vLLM API error',
              statusCode: res.statusCode,
              responseBody: await _httpHelper.readErrorBody(res),
            );
          }
          return res;
        },
        config: effectiveRetryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, effectiveRetryConfig),
      ),
    );

    try {
      switch (response.statusCode) {
        case 200:
          final chunkStream = VLLMStreamConverter.toLLMStream(
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
          await VLLMErrorHandler.handleBadRequestError(
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
            defaultMessage: 'vLLM API error',
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
    final body = <String, dynamic>{
      'model': model,
      'input': messages,
      ...options,
    };
    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: vllmEndpoint(baseUrl, 'embeddings'),
          headers: _headers(accept: 'application/json'),
          body: json.encode(body),
        ),
        config: retryConfig ?? defaultRetryConfig,
        isRetryable: (error) => ErrorHandlers.isRetryableError(
          error,
          retryConfig ?? defaultRetryConfig,
        ),
      ),
    );
    switch (response.statusCode) {
      case 200:
        return VLLMEmbeddingsResponse.fromJson(
          json.decode(response.body) as Map<String, dynamic>,
        ).toLLMEmbedding;
      case 400:
        // Route through the shared handler so an embedding request against a
        // chat-only model reports the server's own explanation rather than a
        // generic message.
        await VLLMErrorHandler.handleBadRequestError(
          errorBody: response.body,
          model: model,
          thinkRequested: false,
          toolsRequested: false,
        );
        throw LLMApiException(
          'Error generating embedding',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      default:
        _httpHelper.handleHttpError(
          statusCode: response.statusCode,
          errorBody: response.body,
          defaultMessage: 'Error generating embedding',
        );
        throw LLMApiException(
          'Error generating embedding',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
    }
  }

  /// Default number of inputs sent per `/v1/embeddings` request.
  ///
  /// vLLM batches server-side, but a single request still has to fit the
  /// server's max input length and request size limits, so a large list is
  /// split rather than sent whole.
  static const int defaultEmbeddingBatchSize = 32;

  /// Embeds [messages] in batches, preserving input order.
  ///
  /// Override the batch size with `options['batch_size']`; pass `0` to send
  /// everything in one request (the previous behavior).
  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final requested = options['batch_size'];
    final batchSize = requested is int ? requested : defaultEmbeddingBatchSize;
    final embedOptions = Map<String, dynamic>.from(options)
      ..remove('batch_size');

    if (batchSize <= 0 || messages.length <= batchSize) {
      return embed(model: model, messages: messages, options: embedOptions);
    }

    final results = <LLMEmbedding>[];
    for (var start = 0; start < messages.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, messages.length);
      results.addAll(
        await embed(
          model: model,
          messages: messages.sublist(start, end),
          options: embedOptions,
        ),
      );
    }
    return results;
  }

  Map<String, String> _headers({required String accept}) {
    return {
      'content-type': 'application/json',
      'accept': accept,
      if (apiKey != null && apiKey!.isNotEmpty)
        'authorization': 'Bearer $apiKey',
    };
  }

  static void _applyGenerationOptions(
    Map<String, dynamic> body,
    MergedOptions options,
  ) {
    if (options.temperature != null) body['temperature'] = options.temperature;
    if (options.topP != null) body['top_p'] = options.topP;
    if (options.topK != null) body['top_k'] = options.topK;
    if (options.maxOutputTokens != null) {
      body['max_completion_tokens'] = options.maxOutputTokens;
    }
    if (options.stopSequences != null) body['stop'] = options.stopSequences;

    // Reasoning control.
    //
    // vLLM separates two concerns that look like one:
    //
    //   chat_template_kwargs.enable_thinking — whether the model thinks at all
    //   include_reasoning                    — whether reasoning is surfaced
    //
    // `include_reasoning` exists but defaults to `true`, and setting it to
    // `false` *discards* the reasoning while the model still spends tokens
    // producing it. It is therefore the wrong knob for `think: false`; the
    // chat template is what actually gates thinking, and Qwen3-family
    // templates read `enable_thinking`.
    //
    // Sent for `false` as well as `true`, because Qwen3 thinks by default and
    // would otherwise ignore `think: false`.
    //
    // `thinking_token_budget` IS a real vLLM field, but the server rejects it
    // with a 400 unless it was started with `--reasoning-parser` /
    // `--reasoning-config`. It is therefore opt-in rather than implicit: set
    // `backendOptions['thinking_token_budget']` when the server supports it.
    final templateKwargs = <String, dynamic>{
      ...?body['chat_template_kwargs'] as Map<String, dynamic>?,
      'enable_thinking': options.think,
    };
    body['chat_template_kwargs'] = templateKwargs;
  }

  /// Collapses runs of adjacent system messages into one.
  ///
  /// Chat templates disagree on how many system messages they accept. Several
  /// — including Qwen3's — allow exactly one, at position 0, and reject
  /// anything else with `System message must be at the beginning`, even when
  /// every system message *is* at the beginning. Callers building a prompt
  /// from composable fragments hit this routinely.
  ///
  /// Adjacent system messages are joined with a blank line, which is lossless
  /// and matches how `llm_claude` builds its `system` field. Non-adjacent
  /// system messages are left in place: moving them would change the
  /// conversation's meaning, and some templates legitimately support them.
  static List<LLMMessage> _mergeConsecutiveSystemMessages(
    List<LLMMessage> messages,
  ) {
    if (messages.length < 2) return messages;

    final merged = <LLMMessage>[];
    for (final message in messages) {
      final previous = merged.isEmpty ? null : merged.last;
      final canMerge =
          message.role == LLMRole.system &&
          previous?.role == LLMRole.system &&
          previous?.content != null &&
          message.content != null &&
          (message.images?.isEmpty ?? true) &&
          (previous?.images?.isEmpty ?? true);

      if (canMerge) {
        merged[merged.length - 1] = LLMMessage(
          role: LLMRole.system,
          content: '${previous!.content}\n\n${message.content}',
        );
      } else {
        merged.add(message);
      }
    }
    return merged;
  }

  /// `tool_choice` values vLLM accepts verbatim; anything else is treated as a
  /// tool name and wrapped in the named-function form.
  static const Set<String> _openAiToolChoiceModes = {
    'auto',
    'none',
    'required',
  };

  /// Copies validated backend options onto the request body.
  ///
  /// Keys are normalized to their wire spelling (so `topP` becomes `top_p`
  /// rather than being silently dropped), and a nested `extra_body` map is
  /// flattened — `extra_body` is an OpenAI *Python SDK* wrapper, not a wire
  /// field, so vLLM never reads it.
  ///
  /// Validation runs before this in [streamChat]; by the time it is called the
  /// keys are known-good.
  static void _applyBackendOptions(
    Map<String, dynamic> body,
    Map<String, dynamic> backendOptions,
  ) {
    for (final entry in backendOptions.entries) {
      if (entry.key == 'extra_body' && entry.value is Map<String, dynamic>) {
        _applyBackendOptions(body, entry.value as Map<String, dynamic>);
        continue;
      }
      final key = normalizeVllmParam(entry.key);
      // Consumed above; the raw value would overwrite the converted one.
      if (key == 'tool_choice') continue;
      body[key] = entry.value;
    }
  }

  /// Rejects backend options vLLM would silently drop or that this repository
  /// builds itself.
  ///
  /// [knownParams] defaults to the [knownVllmChatParams] snapshot; pass the
  /// result of `VLLMRepository.fetchSupportedParams()` to validate against a
  /// specific server's schema instead.
  static void _validateBackendOptions(
    Map<String, dynamic> backendOptions, {
    Set<String>? knownParams,
  }) {
    if (backendOptions.isEmpty) return;
    final errors = validateVllmParams(backendOptions, knownParams: knownParams);
    if (errors.isEmpty) return;
    throw ArgumentError(
      errors.length == 1
          ? errors.single.message
          : 'Invalid backendOptions:\n'
                '${errors.map((e) => '  - ${e.message}').join('\n')}',
    );
  }

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
}
