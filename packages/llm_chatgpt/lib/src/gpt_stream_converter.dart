import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/src/dto/gpt_chunk.dart';
import 'package:llm_chatgpt/src/dto/gpt_stream_decoder.dart';
import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';
import 'package:llm_core/llm_core.dart';

/// Converts ChatGPT streaming responses to LLM chunks.
class GPTStreamConverter {
  /// Converts an HTTP streamed response to a stream of LLM chunks.
  ///
  /// [response] - The streamed HTTP response from OpenAI
  static Stream<LLMChunk> toLLMStream(http.StreamedResponse response) async* {
    // Accumulated calls in arrival order, plus a map from the wire `index`
    // to the position of the call currently open at that index.
    //
    // Neither field alone is enough. Continuation fragments carry `id: null`
    // by design, so id cannot correlate them — but some OpenAI-compatible
    // proxies emit every parallel call with `index: 0`, so index alone merges
    // distinct calls into one malformed blob. A fragment that carries an id
    // different from the call open at its index therefore starts a new call.
    final accumulated = <GPTToolCall>[];
    final openAt = <int, int>{};

    await for (final output
        in response.stream
            .transform(utf8.decoder)
            .transform(GPTStreamDecoder.decoder)) {
      if (output != '[DONE]') {
        try {
          final decoded = json.decode(output);
          if (decoded is Map<String, dynamic> && decoded['error'] != null) {
            // An in-stream error must surface as a thrown exception. Parsed as
            // an ordinary frame it has no choices and no usage, so it was
            // skipped and the stream ended as a *success* carrying a truncated
            // answer.
            throw _streamError(decoded['error'], output);
          }
          final chunk = GPTChunk.fromJson(decoded);

          if (chunk.choices.isEmpty) {
            // Usage-only frame sent when `stream_options.include_usage` is on.
            if (chunk.usage != null) {
              yield chunk;
            }
            continue;
          }

          final rawToolCallDeltas = chunk.choices[0].delta.toolCalls;
          for (final toolCall in rawToolCallDeltas ?? <GPTToolCall>[]) {
            final position = openAt[toolCall.index];
            final id = toolCall.id;
            final startsNewCall =
                position == null ||
                (id != null && id.isNotEmpty && accumulated[position].id != id);
            if (startsNewCall) {
              openAt[toolCall.index] = accumulated.length;
              accumulated.add(toolCall);
            } else {
              accumulated[position] = accumulated[position].copyWith(
                newFunction: toolCall.function,
              );
            }
          }

          final finishReason = chunk.choices[0].finishReason;
          // An empty content delta is the priming event announcing the
          // assistant role, not output.
          final content = chunk.choices[0].delta.content;
          final hasContent = content != null && content.isNotEmpty;
          final thinking = chunk.choices[0].delta.thinking;
          var emitted = false;

          if ((hasContent || thinking != null) && finishReason == null) {
            emitted = true;
            yield chunk;
          }

          if (finishReason == 'tool_calls' && accumulated.isNotEmpty) {
            final toolCallChunk = GPTChunk(
              id: chunk.id,
              created: chunk.created,
              model: chunk.model,
              systemFingerprint: chunk.systemFingerprint,
              choices: [
                GPTChunkChoice(
                  index: 0,
                  delta: GPTChunkChoiceDelta(
                    role: null,
                    content: null,
                    toolCalls: List<GPTToolCall>.from(accumulated),
                  ),
                  logProbs: null,
                  finishReason: 'tool_calls',
                ),
              ],
            );
            emitted = true;
            yield toolCallChunk;
          } else if (finishReason != null && finishReason != 'tool_calls') {
            emitted = true;
            yield chunk;
          }

          if (!emitted &&
              rawToolCallDeltas != null &&
              rawToolCallDeltas.isNotEmpty) {
            // A fragment-only event, which previously yielded nothing at all.
            yield _toolCallDeltaChunk(chunk, rawToolCallDeltas);
          }
        } on LLMApiException {
          // A real API failure, not a malformed frame — never swallow it.
          rethrow;
        } catch (e) {
          // Continue stream on parse errors
        }
      }
    }
  }

  /// Builds the exception for an in-stream `error` event.
  ///
  /// The code is surfaced as [LLMApiException.statusCode] because retry
  /// classification works off the status code — without it a mid-stream
  /// 429 or 503 could never be recognized as retryable.
  static LLMApiException _streamError(Object error, String rawEvent) {
    final code = error is Map<String, dynamic>
        ? (error['code'] ?? error['status'])
        : null;
    final statusCode = switch (code) {
      int() => code,
      String() => int.tryParse(code),
      _ => null,
    };
    return LLMApiException(
      'OpenAI stream error: $error',
      statusCode: statusCode,
      responseBody: rawEvent,
    );
  }

  /// Builds a progress chunk carrying the fragments from a single event.
  ///
  /// `toolCalls` is deliberately left null: only complete, executable calls
  /// belong there, and [StreamToolExecutor] dispatches whatever it finds.
  static GPTChunk _toolCallDeltaChunk(
    GPTChunk source,
    List<GPTToolCall> rawDeltas,
  ) {
    return GPTChunk(
      id: source.id,
      created: source.created,
      model: source.model,
      systemFingerprint: source.systemFingerprint,
      choices: [
        GPTChunkChoice(
          index: 0,
          delta: GPTChunkChoiceDelta(
            // Set explicitly: a fragment-only event carries no role, and role
            // inference has nothing else to go on.
            role: LLMRole.assistant.name,
            content: null,
            toolCalls: null,
            toolCallDeltas: rawDeltas,
          ),
          logProbs: null,
          finishReason: null,
        ),
      ],
    );
  }
}
