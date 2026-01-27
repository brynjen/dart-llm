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
class OllamaChatRepository extends LLMChatRepository {
  OllamaChatRepository({
    String? baseUrl,
    this.maxToolAttempts = 25,
    this.retryConfig,
    this.timeoutConfig,
    http.Client? httpClient,
  }) : baseUrl = baseUrl ?? 'http://localhost:11434',
       httpClient = httpClient ?? http.Client(),
       _httpHelper = HttpClientHelper(
         httpClient: httpClient ?? http.Client(),
         timeoutConfig: timeoutConfig,
       ),
       _ollamaRepo = OllamaRepository(
         baseUrl: baseUrl ?? 'http://localhost:11434',
         httpClient: httpClient,
       );

  /// The base URL of the Ollama server.
  final String baseUrl;

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

  final OllamaRepository _ollamaRepo;

  Uri get uri => Uri.parse('$baseUrl/api/chat');

  /// Create a builder for configuring a new repository instance.
  static OllamaChatRepositoryBuilder builder() {
    return OllamaChatRepositoryBuilder();
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

    if (messages.any((msg) => msg.images != null && msg.images!.isNotEmpty)) {
      if (!(await _ollamaRepo.supportsVision(model))) {
        throw VisionNotSupportedException(
          model,
          'Model $model does not support vision/images',
        );
      }
    }

    final body = {
      'model': model,
      'messages': messages
          .map((msg) => OllamaMessageConverter.toJson(msg))
          .toList(growable: false),
      'stream': true,
      'think': merged.think,
    };
    if (merged.tools.isNotEmpty) {
      body['tools'] = merged.tools
          .map((tool) => tool.toJson)
          .toList(growable: false);
    }

    final response = await _httpHelper.sendStreamingRequest(
      method: 'POST',
      uri: uri,
      headers: {'content-type': 'application/json'},
      body: utf8.encode(json.encode(body)),
      applyTimeoutToSend: false, // Timeout applied when reading stream
    );

    try {
      switch (response.statusCode) {
        case 200:
          final chunkStream = OllamaStreamConverter.toLLMStream(
            response,
            timeoutConfig: timeoutConfig,
          );
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
    final body = {'model': model, 'input': messages, 'options': options};
    final response = await RetryUtil.executeWithRetry(
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
}
