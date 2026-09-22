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
    // Ollama delivers complete tool calls on an earlier frame and the finish
    // on the terminal one, so the terminal frame alone cannot tell whether the
    // turn called a tool. One HTTP response is one turn — the loop re-issues a
    // request per round — so this never needs resetting.
    var turnCarriedToolCalls = false;

    try {
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
            if (ollamaChunk.message?.toolCalls?.isNotEmpty ?? false) {
              turnCarriedToolCalls = true;
            }
            yield (ollamaChunk.done ?? false)
                ? _withResolvedFinishReason(ollamaChunk, turnCarriedToolCalls)
                : ollamaChunk;
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
    } on http.RequestAbortedException {
      // A deliberate stop, not a failure. `http` signals an abort by
      // injecting this into the response stream; surfacing it would make a
      // cancelled turn look like a transport error, and `cancel()` itself
      // complete with an error. Returning skips any end-of-stream flush
      // below: an abandoned turn has no partial output worth surfacing.
      return;
    }

    final trailingLine = carryBuffer.toString().trim();
    if (trailingLine.isNotEmpty) {
      _recordMalformedLine(
        line: trailingLine,
        malformedLineCount: malformedLineCount,
      );
    }
  }

  /// Rebuilds a terminal chunk whose finish reason disagrees with the calls
  /// the turn actually produced.
  ///
  /// Ollama's `done_reason` is `stop` even for a turn that called a tool, and
  /// the calls arrive on the frame before the terminal one. Per the OpenAI
  /// specification `finish_reason` is `tool_calls` "if the model called a
  /// tool", so the turn is reclassified here rather than in
  /// [OllamaChunk.fromJson] — the DTO parses a single frame and has no way to
  /// know what the rest of the turn carried.
  static OllamaChunk _withResolvedFinishReason(
    OllamaChunk chunk,
    bool turnCarriedToolCalls,
  ) {
    final resolved = LLMFinishReason.resolve(
      reported: chunk.finishReason,
      hasCompleteToolCalls: turnCarriedToolCalls,
    );
    if (resolved == chunk.finishReason) return chunk;
    return OllamaChunk(
      model: chunk.model,
      createdAt: chunk.createdAt,
      message: chunk.message,
      done: chunk.done,
      promptEvalCount: chunk.promptEvalCount,
      evalCount: chunk.evalCount,
      finishReason: resolved,
    );
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
