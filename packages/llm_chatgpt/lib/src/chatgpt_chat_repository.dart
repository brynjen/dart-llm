import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_chatgpt/src/chatgpt_chat_repository_builder.dart';
import 'package:llm_chatgpt/src/dto/gpt_embedding_response.dart';
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
class ChatGPTChatRepository extends LLMChatRepository {
  ChatGPTChatRepository({
    required this.apiKey,
    this.baseUrl = 'https://api.openai.com',
    this.maxToolAttempts = 25,
    this.retryConfig,
    this.timeoutConfig,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _httpHelper = HttpClientHelper(
         httpClient: httpClient ?? http.Client(),
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

  /// The maximum number of tool attempts to make for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  Uri get uri => Uri.parse('$baseUrl/v1/chat/completions');

  /// Create a builder for configuring a new repository instance.
  static ChatGPTChatRepositoryBuilder builder() {
    return ChatGPTChatRepositoryBuilder();
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

    final response = await RetryUtil.executeWithRetry(
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
      ),
      config: retryConfig,
      isRetryable: (error) =>
          ErrorHandlers.isRetryableError(error, retryConfig),
    );
    try {
      switch (response.statusCode) {
        case 200:
          final chunkStream = GPTStreamConverter.toLLMStream(response);
          if (merged.tools.isNotEmpty) {
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
                    toolAttempts: toolAttempts,
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

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final body = {'model': model, 'input': messages};
    final response = await RetryUtil.executeWithRetry(
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
}
