import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';

import 'package:llm_chatgpt/src/dto/gpt_embedding_response.dart';
import 'package:llm_chatgpt/src/dto/gpt_response.dart';
import 'package:llm_chatgpt/src/dto/gpt_stream_decoder.dart';

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
  }) : httpClient = httpClient ?? http.Client();

  /// The base URL for the OpenAI API.
  final String baseUrl;

  /// The API key for OpenAI.
  final String apiKey;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// The maximum number of tool attempts to make for a single request.
  final int maxToolAttempts;

  /// Retry configuration for transient failures.
  final RetryConfig? retryConfig;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  Uri get uri => Uri.parse('$baseUrl/v1/chat/completions');

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
    final effectiveTools = options?.tools.isNotEmpty == true
        ? options!.tools
        : tools;
    final effectiveExtra = options?.extra ?? extra;
    final effectiveToolAttempts = options?.toolAttempts ?? toolAttempts;

    final body = {
      'model': model,
      'messages': messages.map((msg) => msg.toJson()).toList(growable: false),
      'stream': true,
    };
    if (effectiveTools.isNotEmpty) {
      body['tools'] = effectiveTools
          .map((tool) => tool.toJson)
          .toList(growable: false);
    }

    final response = await RetryUtil.executeWithRetry(
      operation: () => _sendStreamingRequest('POST', uri, body: body),
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
    try {
      switch (response.statusCode) {
        case 200: // HttpStatus.ok
          yield* toLLMStream(
            response,
            model: model,
            tools: effectiveTools,
            messages: messages,
            extra: effectiveExtra,
            toolAttempts: effectiveToolAttempts ?? maxToolAttempts,
          );
        default:
          // Read the error response body
          final errorBody = await response.stream
              .transform(utf8.decoder)
              .join();
          throw LLMApiException(
            'OpenAI API error',
            statusCode: response.statusCode,
            responseBody: errorBody,
          );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendStreamingRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.StreamedRequest(method, uri);
    request.headers['content-type'] = 'application/json';
    request.headers['accept'] = 'text/event-stream';
    request.headers['authorization'] = 'Bearer $apiKey';

    if (body != null) {
      final bodyBytes = utf8.encode(json.encode(body));
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
      'authorization': 'Bearer $apiKey',
    };

    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final payloadSize = body != null ? json.encode(body).length : 0;
    final readTimeout = config.getReadTimeoutForPayload(payloadSize);

    final response = method.toUpperCase() == 'POST'
        ? await httpClient
              .post(
                uri,
                headers: headers,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(readTimeout)
        : await httpClient.get(uri, headers: headers).timeout(readTimeout);

    return response;
  }

  /// Converts the HTTP stream to an LLM chunk stream.
  Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    required String model,
    required List<LLMMessage> messages,
    required List<LLMTool> tools,
    dynamic extra,
    Map<String, dynamic> options = const {},
    int toolAttempts = 5,
  }) async* {
    final List<LLMMessage> workingMessages = List.from(messages);
    final Map<String, GPTToolCall> toolsToCall = {};

    await for (final output
        in response.stream
            .transform(utf8.decoder)
            .transform(GPTStreamDecoder.decoder)) {
      if (output != '[DONE]') {
        try {
          final chunk = GPTChunk.fromJson(json.decode(output));
          for (final toolCall
              in chunk.choices[0].delta.toolCalls ?? <GPTToolCall>[]) {
            if (toolCall.id != null) {
              toolsToCall[toolCall.id!] = toolCall;
            } else if (toolsToCall.isNotEmpty) {
              // Only access .last if there are keys
              final lastId = toolsToCall.keys.last;
              final updatedTool = toolsToCall[lastId]?.copyWith(
                newFunction: toolCall.function,
              );
              if (updatedTool != null) {
                toolsToCall[lastId] = updatedTool;
              }
            }
          }
          final finishReason = chunk.choices[0].finishReason;
          final content = chunk.choices[0].delta.content;

          if (content != null && finishReason == null) {
            yield chunk;
          }
          if (finishReason != null) {
            if (finishReason == 'tool_calls' && toolsToCall.isNotEmpty) {
              // Only proceed if we have actual tool calls
              final toolCallsList = toolsToCall.values
                  .map(
                    (toolCall) => {
                      'id': toolCall.id,
                      'type': 'function',
                      'function': {
                        'name': toolCall.function.name,
                        'arguments': toolCall.function.arguments,
                      },
                    },
                  )
                  .toList();

              // Only add the assistant message if we have valid tool calls
              if (toolCallsList.isNotEmpty) {
                workingMessages.add(
                  LLMMessage(
                    content: null,
                    role: LLMRole.assistant,
                    toolCalls: toolCallsList,
                  ),
                );

                // Then add tool response messages
                for (final toolCall in toolsToCall.values) {
                  final function = toolCall.function;
                  final tool = tools.firstWhere(
                    (t) => t.name == toolCall.function.name,
                    orElse: () => throw Exception(
                      'Tool ${toolCall.function.name} not found',
                    ),
                  );
                  final toolResponse =
                      await tool.execute(
                        json.decode(function.arguments),
                        extra: extra,
                      ) ??
                      'Unable to use not-existing tool ${function.name}';
                  workingMessages.add(
                    LLMMessage(
                      content: toolResponse,
                      role: LLMRole.tool,
                      toolCallId: toolCall.id,
                    ),
                  );
                  toolAttempts--;
                }
                yield* streamChat(
                  model,
                  messages: workingMessages,
                  tools: tools,
                  toolAttempts: toolAttempts,
                  extra: extra,
                );
              }
            }
          }
        } catch (e) {
          // Don't rethrow here to allow stream to continue
        }
      }
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
      operation: () => _sendNonStreamingRequest(
        'POST',
        Uri.parse('$baseUrl/v1/embeddings'),
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
