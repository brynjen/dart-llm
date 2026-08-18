import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/dto/vllm_embedding_response.dart';
import 'package:llm_vllm/src/vllm_error_handler.dart';
import 'package:llm_vllm/src/vllm_base_url.dart';
import 'package:llm_vllm/src/vllm_trace.dart';
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
         httpClient:
             httpClient ?? createLLMHttpClient(timeoutConfig: timeoutConfig),
         ownsHttpClient: httpClient == null,
       );

  VLLMChatRepository._({
    required this.baseUrl,
    required this.apiKey,
    required this.maxToolAttempts,
    required this.retryConfig,
    required this.timeoutConfig,
    required this.httpClient,
    required this._ownsHttpClient,
    this.supportedParams,
    this.capabilities,
    RateLimiter? rateLimiter,
    this.responseCache,
    this.metrics,
  }) : _rateLimiter = rateLimiter?.enabled == true
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
    }

    _validateBackendOptions(
      merged.backendOptions,
      knownParams: supportedParams,
    );
    // Normalized *after* validation (which reports the caller's spelling) and
    // used for every read below. Reading the raw map by wire name is how an
    // aliased key — `toolChoice` for `tool_choice` — used to pass validation
    // and then silently never reach the request.
    final backendOptions = normalizeVllmParams(merged.backendOptions);
    _rejectMultipleCandidates(backendOptions);
    _applyToolChoice(body, backendOptions, hasTools: merged.tools.isNotEmpty);
    _applyGenerationOptions(body, merged);
    _applyBackendOptions(body, backendOptions);
    _applyResponseFormat(body, merged.responseFormat);

    final traceId = vllmNextRequestId();
    vllmTrace(traceId, 'request.build', 'model=$model uri=$uri');

    Future<http.StreamedResponse>
    send() => RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () async {
          vllmTrace(traceId, 'send.begin');
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
          vllmTrace(traceId, 'send.headers', 'status=${res.statusCode}');
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

    var response = await send();
    vllmTrace(traceId, 'send.done', 'status=${response.statusCode}');

    // Each served model validates `reasoning_effort` against its own
    // vocabulary (Qwen3.8: low/medium/xhigh), discoverable only through the
    // 400 it returns. Remap once to the nearest supported level and resend so
    // the portable effort scale works regardless of the model's dialect.
    if (response.statusCode == 400 && body['reasoning_effort'] is String) {
      final errorBody = await _httpHelper.readErrorBody(response);
      final remapped = remapVllmReasoningEffort(
        body['reasoning_effort'] as String,
        errorBody,
      );
      if (remapped == null) {
        await VLLMErrorHandler.handleBadRequestError(
          errorBody: errorBody,
          model: model,
          thinkRequested: merged.think,
          toolsRequested: merged.tools.isNotEmpty,
        );
      }
      body['reasoning_effort'] = remapped;
      response = await send();
    }

    switch (response.statusCode) {
      case 200:
        vllmTrace(traceId, 'stream.open');
        final chunkStream = VLLMStreamConverter.toLLMStream(
          response,
          timeoutConfig: timeoutConfig,
          traceId: traceId,
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
                    backendOptions: backendOptions,
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
        await VLLMErrorHandler.handleBadRequestError(
          errorBody: errorBody,
          model: model,
          thinkRequested: merged.think,
          toolsRequested: merged.tools.isNotEmpty,
        );
      default:
        final errorBody = await _httpHelper.readErrorBody(response);
        _httpHelper.handleHttpError(
          statusCode: response.statusCode,
          errorBody: errorBody,
          defaultMessage: 'vLLM API error',
        );
    }
  }

  /// Keys interpreted client-side by `embed`/`batchEmbed`; never sent.
  static const Set<String> _clientSideEmbedKeys = {
    'batch_size',
    'batchSize',
    'timeout',
  };

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    Validation.validateModelName(model);
    if (messages.isEmpty) {
      throw ArgumentError('messages must not be empty');
    }

    final timeout = options['timeout'];
    if (timeout != null && timeout is! Duration) {
      throw ArgumentError(
        'options["timeout"] must be a Duration, got ${timeout.runtimeType}',
      );
    }

    // Validated like chat's backendOptions, and for the same reason: vLLM
    // silently drops unknown fields, so an unvalidated typo here looks like a
    // successful request with the option never applied.
    final wireOptions = Map<String, dynamic>.from(options)
      ..removeWhere((key, _) => _clientSideEmbedKeys.contains(key));
    _validateBackendOptions(
      wireOptions,
      knownParams: knownVllmEmbeddingParams,
      reservedParams: reservedVllmEmbeddingParams,
      path: 'options',
    );

    final body = <String, dynamic>{
      'model': model,
      'input': messages,
      ...normalizeVllmParams(wireOptions),
    };
    final response = await RateLimiterUtil.executeWithRateLimit(
      rateLimiter: _rateLimiter,
      operation: () => RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: vllmEndpoint(baseUrl, 'embeddings'),
          headers: _headers(accept: 'application/json'),
          body: json.encode(body),
          timeout: timeout as Duration?,
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
        try {
          return VLLMEmbeddingsResponse.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ).toLLMEmbedding;
        } on FormatException catch (e) {
          throw LLMApiException(
            'Malformed vLLM embeddings response: ${e.message}',
            statusCode: 200,
            responseBody: response.body,
          );
        } on TypeError {
          throw LLMApiException(
            'Malformed vLLM embeddings response',
            statusCode: 200,
            responseBody: response.body,
          );
        }
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
    final requested = options['batch_size'] ?? options['batchSize'];
    final batchSize = requested is int ? requested : defaultEmbeddingBatchSize;
    final embedOptions = Map<String, dynamic>.from(options)
      ..remove('batch_size')
      ..remove('batchSize');

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
    var enableThinking = options.think;

    if (options.think) {
      if (options.reasoningBudget != null) {
        // vLLM ≥0.19 enforces `thinking_token_budget` server-side (a logits
        // processor forces the end-of-thinking tokens once the budget is
        // spent), but only when the server runs with `--reasoning-parser`.
        // Without the parser the server answers 400, which the error handler
        // maps to [ThinkingNotSupportedException]. Top-level on purpose:
        // routed through `vllm_xargs`/`extra_args` it is silently ignored on
        // pre-0.19 servers.
        body['thinking_token_budget'] = options.reasoningBudget;
      } else if (options.reasoningEffort != null) {
        // No exact budget requested: use vLLM's native `reasoning_effort`,
        // which needs no reasoning parser. vLLM accepts only low/medium/high,
        // so the portable scale is clamped; `none` suppresses thinking via
        // the chat template instead, since vLLM has no effort value for it.
        switch (options.reasoningEffort!) {
          case ReasoningEffort.none:
            enableThinking = false;
          case ReasoningEffort.minimal:
          case ReasoningEffort.low:
            body['reasoning_effort'] = 'low';
          case ReasoningEffort.medium:
            body['reasoning_effort'] = 'medium';
          case ReasoningEffort.high:
          case ReasoningEffort.xhigh:
          case ReasoningEffort.max:
            body['reasoning_effort'] = 'high';
        }
      }
    }

    final templateKwargs = <String, dynamic>{
      ...?body['chat_template_kwargs'] as Map<String, dynamic>?,
      'enable_thinking': enableThinking,
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

  /// Applies `tool_choice` from the normalized [backendOptions] to the body.
  ///
  /// `tool_choice` is OpenAI-compatible on vLLM. Both "auto" and "required"
  /// need the server started with --tool-call-parser; without it vLLM rejects
  /// the request rather than ignoring the field.
  ///
  /// Applied whether or not tools are present: `none` and `auto` are valid on
  /// a tool-less request and vLLM accepts them. `required` or a specific tool
  /// cannot be satisfied without tools — vLLM answers 400 — so that case is
  /// rejected here, naming the actual problem instead of surfacing a server
  /// error about a request the caller never meant to send.
  static void _applyToolChoice(
    Map<String, dynamic> body,
    Map<String, dynamic> backendOptions, {
    required bool hasTools,
  }) {
    final toolChoice = backendOptions['tool_choice'];
    if (toolChoice == null) return;

    final isPassthroughMode =
        toolChoice is String && _openAiToolChoiceModes.contains(toolChoice);
    final needsTools = !isPassthroughMode || toolChoice == 'required';
    if (!hasTools && needsTools) {
      throw ArgumentError(
        'tool_choice "$toolChoice" requires at least one tool, but the '
        'request has none. Pass the tools alongside it, or use "none"/"auto".',
      );
    }

    body['tool_choice'] = isPassthroughMode || toolChoice is! String
        ? toolChoice
        : {
            'type': 'function',
            'function': {'name': toolChoice},
          };
  }

  /// Rejects `n > 1`: the streaming pipeline surfaces only `choices[0]`, so
  /// additional candidates would be generated, paid for, and discarded.
  static void _rejectMultipleCandidates(Map<String, dynamic> backendOptions) {
    final n = backendOptions['n'];
    if (n != null && n != 1) {
      throw ArgumentError(
        'backendOptions "n" must be 1 (got $n): this repository streams a '
        'single completion and discards additional candidates, so they would '
        'only cost tokens. Issue separate requests for multiple candidates.',
      );
    }
  }

  /// Copies validated, normalized backend options onto the request body.
  ///
  /// Keys arrive already alias-normalized and `extra_body`-flattened (see
  /// [normalizeVllmParams] in [streamChat]); by the time this is called they
  /// are known-good wire names.
  static void _applyBackendOptions(
    Map<String, dynamic> body,
    Map<String, dynamic> backendOptions,
  ) {
    for (final entry in backendOptions.entries) {
      // Consumed by _applyToolChoice; the raw value would overwrite the
      // converted one.
      if (entry.key == 'tool_choice') continue;
      // _applyGenerationOptions has already written `enable_thinking` here. A
      // wholesale assignment would silently discard it — and with it the
      // `think:` flag — whenever a caller sets unrelated template kwargs.
      // Merge key-by-key instead; the caller's entries win, so an explicit
      // `enable_thinking` still overrides `think:`, consistent with how
      // scalar backend options take precedence over typed options.
      if (entry.key == 'chat_template_kwargs' &&
          entry.value is Map<String, dynamic>) {
        body['chat_template_kwargs'] = <String, dynamic>{
          ...?body['chat_template_kwargs'] as Map<String, dynamic>?,
          ...entry.value as Map<String, dynamic>,
        };
        continue;
      }
      body[entry.key] = entry.value;
    }
  }

  /// Rejects options vLLM would silently drop or that this repository builds
  /// itself.
  ///
  /// [knownParams] defaults to the [knownVllmChatParams] snapshot; pass the
  /// result of `VLLMRepository.fetchSupportedParams()` to validate against a
  /// specific server's schema instead. `embed` passes
  /// [knownVllmEmbeddingParams]/[reservedVllmEmbeddingParams], since the two
  /// endpoints accept different parameter sets.
  static void _validateBackendOptions(
    Map<String, dynamic> backendOptions, {
    Set<String>? knownParams,
    Set<String>? reservedParams,
    String path = 'backendOptions',
  }) {
    if (backendOptions.isEmpty) return;
    final errors = validateVllmParams(
      backendOptions,
      knownParams: knownParams,
      reservedParams: reservedParams,
      path: path,
    );
    if (errors.isEmpty) return;
    throw ArgumentError(
      errors.length == 1
          ? errors.single.message
          : 'Invalid $path:\n'
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
