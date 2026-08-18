import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/dto/ollama_response.dart';

/// Converts Ollama streaming responses to LLM chunks.
class OllamaStreamConverter {
  static const int _maxMalformedLineRetries = 3;

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
    final carryBuffer = StringBuffer();
    var malformedLineCount = 0;

    await for (final chunk
        in response.stream
            .transform(utf8.decoder)
            .timeout(
              readTimeout,
              // The error must be pushed into the sink, not thrown. `onTimeout`
              // runs from a timer, outside the stream's own error path, so a
              // throw here escapes as an unhandled exception and takes the
              // isolate down instead of failing this one request.
              onTimeout: (sink) {
                sink.addError(
                  TimeoutException(
                    'Stream read timed out after ${readTimeout.inSeconds} '
                    'seconds',
                    readTimeout,
                  ),
                );
                sink.close();
              },
            )) {
      carryBuffer.write(chunk);
      final bufferedChunk = carryBuffer.toString();
      final lines = bufferedChunk.split('\n');
      carryBuffer
        ..clear()
        ..write(lines.removeLast());

      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) {
          continue;
        }

        try {
          final decoded = json.decode(trimmedLine);
          if (decoded is Map<String, dynamic> && decoded['error'] != null) {
            throw LLMApiException('Ollama stream error: ${decoded['error']}');
          }
          final ollamaChunk = OllamaChunk.fromJson(decoded);
          yield ollamaChunk;
          malformedLineCount = 0;
        } on LLMApiException {
          rethrow;
        } catch (_) {
          malformedLineCount = _recordMalformedLine(
            line: trimmedLine,
            malformedLineCount: malformedLineCount,
          );
        }
      }
    }

    final trailingLine = carryBuffer.toString().trim();
    if (trailingLine.isNotEmpty) {
      _recordMalformedLine(
        line: trailingLine,
        malformedLineCount: malformedLineCount,
      );
    }
  }

  static int _recordMalformedLine({
    required String line,
    required int malformedLineCount,
  }) {
    final updatedMalformedLineCount = malformedLineCount + 1;
    if (updatedMalformedLineCount > _maxMalformedLineRetries) {
      final preview = _linePreview(line);
      throw LLMApiException(
        'Failed to parse Ollama NDJSON stream after $_maxMalformedLineRetries malformed lines. '
        'Last line preview: $preview',
      );
    }
    return updatedMalformedLineCount;
  }

  static String _linePreview(String line, {int maxLength = 160}) {
    if (line.length <= maxLength) {
      return line;
    }
    return '${line.substring(0, maxLength)}...';
  }
}
