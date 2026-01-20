import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';

import 'package:llm_ollama/src/dto/ollama_embedding_response.dart';
import 'package:llm_ollama/src/dto/ollama_response.dart';

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
    this.baseUrl = 'http://localhost:11434',
    this.maxToolAttempts = 25,
    this.retryConfig,
    this.timeoutConfig,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  /// The base URL of the Ollama server.
  final String baseUrl;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// The maximum number of tool attempts to make for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  Uri get uri => Uri.parse('$baseUrl/api/chat');

  /// Check if a model supports vision by querying its model info.
  /// Vision models have "vision" in their capabilities array.
  Future<bool> _supportsVision(String model) async {
    try {
      final response = await _sendNonStreamingRequest(
        'POST',
        Uri.parse('$baseUrl/api/show'),
        body: {'model': model},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        // Check if model has vision capability
        final capabilities = json['capabilities'] as List<dynamic>?;
        if (capabilities != null) {
          return capabilities.contains('vision');
        }
      }

      // If we can't determine, assume it doesn't support vision to be safe
      return false;
    } catch (e) {
      // If we can't determine, assume it doesn't support vision to be safe
      return false;
    }
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
    // Validate inputs
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    // Merge options with individual parameters (options take precedence)
    final effectiveThink = options?.think ?? think;
    final effectiveTools = options?.tools.isNotEmpty == true
        ? options!.tools
        : tools;
    final effectiveExtra = options?.extra ?? extra;
    final effectiveToolAttempts = options?.toolAttempts ?? toolAttempts;

    // If images are present, check if the model supports vision
    if (messages.any((msg) => msg.images != null && msg.images!.isNotEmpty)) {
      if (!(await _supportsVision(model))) {
        throw VisionNotSupportedException(
          model,
          'Model $model does not support vision/images',
        );
      }
    }

    final body = {
      'model': model,
      'messages': messages
          .map((msg) => _ollamaMessageToJson(msg))
          .toList(growable: false),
      'stream': true,
      'think': effectiveThink,
    };
    if (effectiveTools.isNotEmpty) {
      body['tools'] = effectiveTools
          .map((tool) => tool.toJson)
          .toList(growable: false);
    }

    final response = await RetryUtil.executeWithRetry(
      operation: () => _sendRequest('POST', uri, body: body),
      config: retryConfig,
      isRetryable: (error) {
        // Retry on network errors and retryable HTTP status codes
        if (error is LLMApiException && error.statusCode != null) {
          return retryConfig?.shouldRetryForStatusCode(error.statusCode!) ??
              false;
        }
        return error is TimeoutException ||
            error.toString().toLowerCase().contains('connection') ||
            error.toString().toLowerCase().contains('network');
      },
    );

    try {
      switch (response.statusCode) {
        case 200: // HttpStatus.ok
          yield* toLLMStream(
            response,
            model: model,
            tools: effectiveTools,
            messages: messages,
            toolAttempts: effectiveToolAttempts ?? maxToolAttempts,
            extra: effectiveExtra,
          );
        case 400: // HttpStatus.badRequest
          // Handle 400 errors which might be feature not supported
          final errorBody = await response.stream
              .transform(utf8.decoder)
              .join();
          await _handleBadRequestError(
            errorBody,
            model,
            think,
            tools.isNotEmpty,
          );
          break;
        default:
          final errorBody = await response.stream
              .transform(utf8.decoder)
              .join();
          throw LLMApiException(
            'Request failed',
            statusCode: response.statusCode,
            responseBody: errorBody,
          );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Handle 400 Bad Request errors and throw appropriate exceptions.
  Future<void> _handleBadRequestError(
    String errorBody,
    String model,
    bool thinkRequested,
    bool toolsRequested,
  ) async {
    try {
      final errorData = json.decode(errorBody);
      final errorMessage = errorData['error'] as String? ?? '';

      // Check for thinking not supported error
      if (thinkRequested &&
          errorMessage.contains('does not support thinking')) {
        throw ThinkingNotSupportedException(
          model,
          'Model $model does not support thinking',
        );
      }

      // Check for tools not supported error
      if (toolsRequested && errorMessage.contains('does not support tools')) {
        throw ToolsNotSupportedException(
          model,
          'Model $model does not support tools',
        );
      }

      // Check for chat not supported error (like embedding models)
      if (errorMessage.contains('does not support chat')) {
        throw LLMApiException(
          'Model $model does not support chat - use a chat/completion model instead',
          statusCode: 400,
          responseBody: errorBody,
        );
      }

      // If it's not a specific feature support error, throw a generic error
      throw LLMApiException(
        'Bad request: $errorMessage',
        statusCode: 400,
        responseBody: errorBody,
      );
    } catch (e) {
      if (e is ThinkingNotSupportedException ||
          e is ToolsNotSupportedException ||
          e is LLMApiException) {
        rethrow;
      }
      throw LLMApiException(
        'Bad request',
        statusCode: 400,
        responseBody: errorBody,
      );
    }
  }

  Future<http.StreamedResponse> _sendRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.StreamedRequest(method, uri);
    request.headers['content-type'] = 'application/json';
    request.headers['accept'] = 'text/event-stream';

    if (body != null) {
      final bodyJson = json.encode(body);
      final bodyBytes = utf8.encode(bodyJson);
      request.headers['content-length'] = bodyBytes.length.toString();
      request.sink.add(bodyBytes);
    }
    await request.sink.close();

    // Use configured timeout or default
    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final payloadSize = body != null ? json.encode(body).length : 0;
    final readTimeout = config.getReadTimeoutForPayload(payloadSize);

    return httpClient
        .send(request)
        .timeout(
          readTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Request timed out after ${readTimeout.inSeconds} seconds',
              readTimeout,
            );
          },
        );
  }

  Future<http.Response> _sendNonStreamingRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = {
      'content-type': 'application/json',
      'accept': 'application/json',
    };

    final response = method.toUpperCase() == 'POST'
        ? await httpClient.post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
        : await httpClient.get(uri, headers: headers);

    return response;
  }

  /// Converts the HTTP stream to an LLM chunk stream.
  Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    required String model,
    required List<LLMTool> tools,
    required List<LLMMessage> messages,
    dynamic extra,
    Map<String, dynamic> options = const {},
    int toolAttempts = 5,
  }) async* {
    final List<LLMMessage> workingMessages = List.from(messages);
    final List<dynamic> collectedToolCalls = [];

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        try {
          final chunk = OllamaChunk.fromJson(json.decode(line));
          yield chunk;

          if (chunk.message?.toolCalls != null &&
              chunk.message!.toolCalls!.isNotEmpty) {
            collectedToolCalls.addAll(chunk.message!.toolCalls!);
          }
          if (chunk.done == true && collectedToolCalls.isNotEmpty) {
            for (final toolCall in collectedToolCalls) {
              final tool = tools.firstWhere(
                (t) => t.name == toolCall.name,
                orElse: () =>
                    throw Exception('Tool ${toolCall.name} not found'),
              );
              final toolResponse =
                  await tool.execute(
                    json.decode(toolCall.arguments),
                    extra: extra,
                  ) ??
                  'Tool ${toolCall.name} returned null';
              workingMessages.add(
                LLMMessage(
                  content: toolResponse,
                  role: LLMRole.tool,
                  toolCallId: toolCall.id,
                ),
              );
            }

            if (toolAttempts > 0) {
              yield* streamChat(
                model,
                messages: workingMessages,
                tools: tools,
                extra: extra,
                toolAttempts: toolAttempts - 1,
              );
              return;
            }
          }
        } catch (_) {}
      }
    }
  }

  Map<String, dynamic> _ollamaMessageToJson(LLMMessage message) {
    final json = <String, dynamic>{
      'role': message.role.name,
      'content': message.content ?? '',
    };

    if (message.toolCallId != null) json['tool_call_id'] = message.toolCallId;
    if (message.toolCalls != null) json['tool_calls'] = message.toolCalls;
    if (message.images != null && message.images!.isNotEmpty) {
      json['images'] = message.images;
    }

    return json;
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    final body = {'model': model, 'input': messages, 'options': options};
    final response = await RetryUtil.executeWithRetry(
      operation: () => _sendNonStreamingRequest(
        'POST',
        Uri.parse('$baseUrl/api/embed'),
        body: body,
      ),
      config: retryConfig,
      isRetryable: (error) {
        if (error is LLMApiException && error.statusCode != null) {
          return retryConfig?.shouldRetryForStatusCode(error.statusCode!) ??
              false;
        }
        return error is TimeoutException ||
            error.toString().toLowerCase().contains('connection') ||
            error.toString().toLowerCase().contains('network');
      },
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
