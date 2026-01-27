import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/dto/ollama_response.dart';

/// Converts Ollama streaming responses to LLM chunks.
class OllamaStreamConverter {
  /// Converts an HTTP streamed response to a stream of LLM chunks.
  ///
  /// [response] - The streamed HTTP response from Ollama
  /// [timeoutConfig] - Timeout configuration for reading the stream
  static Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    TimeoutConfig? timeoutConfig,
  }) async* {
    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final readTimeout = config.readTimeout;

    await for (final chunk
        in response.stream
            .transform(utf8.decoder)
            .timeout(
              readTimeout,
              onTimeout: (sink) {
                throw TimeoutException(
                  'Stream read timed out after ${readTimeout.inSeconds} seconds',
                  readTimeout,
                );
              },
            )) {
      final lines = chunk.split('\n').where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        try {
          final ollamaChunk = OllamaChunk.fromJson(json.decode(line));
          yield ollamaChunk;
        } catch (e) {
          continue;
        }
      }
    }
  }
}
