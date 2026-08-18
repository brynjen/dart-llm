import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/timeout_config.dart';

/// Helper class for making HTTP requests with standardized timeout handling
/// and error management.
///
/// This class provides base functionality for streaming and non-streaming
/// HTTP requests that can be extended by backend-specific implementations.
class HttpClientHelper {
  /// Creates an HTTP client helper with the given client and timeout configuration.
  HttpClientHelper({required this.httpClient, this.timeoutConfig});

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// Timeout configuration for requests.
  final TimeoutConfig? timeoutConfig;

  /// Sends a streaming HTTP request with standardized timeout handling.
  ///
  /// [method] - HTTP method (e.g., 'GET', 'POST')
  /// [uri] - Request URI
  /// [headers] - Request headers (backend-specific)
  /// [body] - Request body as bytes (optional)
  /// [applyTimeoutToSend] - Whether to apply timeout to the send operation
  ///   (default: true). Leaving this off returns an entirely untimed
  ///   `send()`, so a request that wedges before response headers arrive
  ///   never recovers — the stream timeouts only start once there is a
  ///   stream to read.
  ///
  /// Returns a [StreamedResponse] that should have timeout applied when reading.
  Future<http.StreamedResponse> sendStreamingRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
    bool applyTimeoutToSend = true,
    Duration? timeout,
  }) async {
    // A plain Request, not a StreamedRequest: every caller passes a
    // fully-materialised body, so there is nothing to stream. package:http
    // derives `content-length` from [bodyBytes] and dart:io writes the body as
    // part of send(). Setting the header by hand on a StreamedRequest instead
    // made IOClient negotiate chunked encoding and then undo it, and left the
    // body behind an unawaited sink close.
    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    if (body != null) {
      request.bodyBytes = body;
    }

    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final payloadSize = body?.length ?? 0;
    final readTimeout = timeout ?? config.getReadTimeoutForPayload(payloadSize);

    if (applyTimeoutToSend) {
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
    } else {
      return httpClient.send(request);
    }
  }

  /// Sends a non-streaming HTTP request with standardized timeout handling.
  ///
  /// [method] - HTTP method (e.g., 'GET', 'POST')
  /// [uri] - Request URI
  /// [headers] - Request headers (backend-specific)
  /// [body] - Request body as string (optional)
  ///
  /// Returns an [http.Response].
  Future<http.Response> sendNonStreamingRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final payloadSize = body?.length ?? 0;
    final readTimeout = timeout ?? config.getReadTimeoutForPayload(payloadSize);

    final response = method.toUpperCase() == 'POST'
        ? await httpClient
              .post(uri, headers: headers, body: body)
              .timeout(readTimeout)
        : await httpClient.get(uri, headers: headers).timeout(readTimeout);

    return response;
  }

  /// Handles HTTP errors and throws appropriate exceptions.
  ///
  /// [statusCode] - HTTP status code
  /// [errorBody] - Error response body
  /// [defaultMessage] - Default error message if status code doesn't match known patterns
  ///
  /// Throws [LLMApiException] with appropriate details.
  void handleHttpError({
    required int statusCode,
    required String errorBody,
    String? defaultMessage,
  }) {
    if (statusCode >= 500) {
      throw LLMApiException(
        defaultMessage ?? 'Server error',
        statusCode: statusCode,
        responseBody: errorBody,
      );
    } else if (statusCode >= 400) {
      throw LLMApiException(
        defaultMessage ?? 'Client error',
        statusCode: statusCode,
        responseBody: errorBody,
      );
    }
  }

  /// Reads the error body from a streamed response.
  ///
  /// [response] - The streamed response to read from
  ///
  /// Returns the error body as a string.
  Future<String> readErrorBody(http.StreamedResponse response) async {
    return await response.stream.transform(utf8.decoder).join();
  }
}
