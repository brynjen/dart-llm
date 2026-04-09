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
/// Example:
/// ```dart
/// final repo = GeminiChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('gemini-2.0-flash', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
class GeminiChatRepository extends LLMChatRepository {
  GeminiChatRepository({
    required this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com',
    this.maxToolAttempts = 90,
    this.retryConfig,
    this.timeoutConfig,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _httpHelper = HttpClientHelper(
         httpClient: httpClient ?? http.Client(),
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

  /// The maximum number of tool attempts for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  static const String _apiVersion = 'v1beta';

  Uri _streamUri(String model) => Uri.parse(
    '$baseUrl/$_apiVersion/models/$model:streamGenerateContent?key=$apiKey&alt=sse',
  );

  Uri _embedUri(String model) =>
      Uri.parse('$baseUrl/$_apiVersion/models/$model:embedContent?key=$apiKey');

  Uri _batchEmbedUri(String model) => Uri.parse(
    '$baseUrl/$_apiVersion/models/$model:batchEmbedContents?key=$apiKey',
  );

  /// Create a builder for configuring a new repository instance.
  static GeminiChatRepositoryBuilder builder() {
    return GeminiChatRepositoryBuilder();
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

    final converted = GeminiMessageConverter.convert(messages);

    final body = <String, dynamic>{'contents': converted.contents};

    if (converted.systemInstruction != null) {
      body['systemInstruction'] = converted.systemInstruction;
    }

    if (merged.tools.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': merged.tools
              .map(GeminiMessageConverter.toolToFunctionDeclaration)
              .toList(growable: false),
        },
      ];
    }

    // generationConfig from backendOptions
    final generationConfig = <String, dynamic>{};
    for (final key in const [
      'temperature',
      'topP',
      'topK',
      'maxOutputTokens',
      'stopSequences',
      'responseMimeType',
    ]) {
      if (merged.backendOptions.containsKey(key)) {
        generationConfig[key] = merged.backendOptions[key];
      }
    }
    // Apply structured output format to generationConfig
    if (merged.responseFormat != null) {
      switch (merged.responseFormat!) {
        case JsonFormat():
          generationConfig['responseMimeType'] = 'application/json';
        case JsonSchemaFormat(:final schema):
          generationConfig['responseMimeType'] = 'application/json';
          generationConfig['responseSchema'] = schema;
      }
    }

    if (generationConfig.isNotEmpty) {
      body['generationConfig'] = generationConfig;
    }

    if (merged.think) {
      final budget = merged.backendOptions['thinking_budget'] ?? 5000;
      body['generationConfig'] = {
        ...generationConfig,
        'thinkingConfig': {'thinkingBudget': budget},
      };
    }

    // Any remaining backend options at top level
    final handledKeys = {
      'temperature',
      'topP',
      'topK',
      'maxOutputTokens',
      'stopSequences',
      'responseMimeType',
      'responseSchema',
      'thinking_budget',
    };
    for (final entry in merged.backendOptions.entries) {
      if (!handledKeys.contains(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await RetryUtil.executeWithRetry(
      operation: () => _httpHelper.sendStreamingRequest(
        method: 'POST',
        uri: _streamUri(model),
        headers: {
          'content-type': 'application/json',
          'accept': 'text/event-stream',
        },
        body: utf8.encode(json.encode(body)),
      ),
      config: retryConfig,
      isRetryable: (error) =>
          ErrorHandlers.isRetryableError(error, retryConfig),
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
      final response = await RetryUtil.executeWithRetry(
        operation: () => _httpHelper.sendNonStreamingRequest(
          method: 'POST',
          uri: _embedUri(model),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: json.encode(body),
        ),
        config: retryConfig,
        isRetryable: (error) =>
            ErrorHandlers.isRetryableError(error, retryConfig),
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
    final response = await RetryUtil.executeWithRetry(
      operation: () => _httpHelper.sendNonStreamingRequest(
        method: 'POST',
        uri: _batchEmbedUri(model),
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: json.encode(body),
      ),
      config: retryConfig,
      isRetryable: (error) =>
          ErrorHandlers.isRetryableError(error, retryConfig),
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
}
