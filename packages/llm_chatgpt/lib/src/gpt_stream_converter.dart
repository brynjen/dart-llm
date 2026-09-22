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
    // Kept so a flush at end of stream can reuse the response's id/model/
    // created instead of inventing them.
    GPTChunk? lastChunk;

    try {
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
                  (id != null &&
                      id.isNotEmpty &&
                      accumulated[position].id != id);
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

            // Classification and emission are separate questions. Whether the
            // turn is a tool-call turn is a protocol rule shared by every
            // backend ([LLMFinishReason.resolve]); whether the accumulated calls
            // get flushed is a question of the turn having ended at all.
            final reported = finishReason == null
                ? null
                : LLMFinishReason.fromProvider(finishReason);
            // The guard is load-bearing: `accumulated` is non-empty from the
            // first fragment, so without it every mid-stream event would read as
            // an end of turn.
            final turnEnded = finishReason != null;
            // A filter or refusal means the provider did not stand behind the
            // calls, so they are not surfaced. Every other ending surfaces them
            // — `length` included, as OpenAI returns them: the reason stays a
            // truncation and the calls come back split by whether their
            // arguments decode.
            final surfacesToolCalls =
                turnEnded &&
                accumulated.isNotEmpty &&
                (reported == null ||
                    reported.canBecomeToolCalls ||
                    reported == LLMFinishReason.length);

            if (surfacesToolCalls) {
              final toolCallChunk = _toolCallChunk(
                chunk,
                accumulated,
                finishReason: LLMFinishReason.resolve(
                  reported: reported,
                  hasCompleteToolCalls: true,
                )!,
              );
              emitted = true;
              accumulated.clear();
              openAt.clear();
              yield toolCallChunk;
            } else if (turnEnded) {
              // Every terminal frame yields exactly one terminal chunk. The old
              // `finishReason != 'tool_calls'` guard meant a `tool_calls` finish
              // with nothing accumulated matched neither branch, so the stream
              // ended with no `done` chunk at all: `chatResponse` reported no
              // usage and a fabricated `stop`, and StreamToolExecutor saw no
              // final assistant answer and threw ToolLoopIncompleteException.
              //
              // Clearing here is what stops the end-of-stream flush resurrecting
              // calls this frame rejected — a filter or refusal means the
              // provider did not stand behind them.
              emitted = true;
              accumulated.clear();
              openAt.clear();
              yield chunk;
            }

            if (!emitted &&
                rawToolCallDeltas != null &&
                rawToolCallDeltas.isNotEmpty) {
              // A fragment-only event, which previously yielded nothing at all.
              yield _toolCallDeltaChunk(chunk, rawToolCallDeltas);
            }
            lastChunk = chunk;
          } on LLMApiException {
            // A real API failure, not a malformed frame — never swallow it.
            rethrow;
          } catch (e) {
            // Continue stream on parse errors
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

    // The stream ended without a terminal frame ever arriving — a proxy cutoff
    // or a server hiccup. Calls complete at that point used to be dropped in
    // silence, because emission was gated on the finish reason alone.
    final pendingCalls = _flushToolCalls(accumulated, lastChunk);
    if (pendingCalls != null) yield pendingCalls;
  }

  /// Emits the calls outstanding when the stream ended without ever sending a
  /// terminal frame, or `null` when nothing was accumulated.
  ///
  /// There is no provider signal at an abrupt end of stream: the same state
  /// describes a finished call and one cut off mid-arguments, and the payload
  /// is the only evidence of which it was. Calls are therefore split by
  /// whether their arguments decode, and empty arguments count as incomplete
  /// — a call that only ever received its name was cut off, not finished.
  static GPTChunk? _flushToolCalls(
    List<GPTToolCall> accumulated,
    GPTChunk? lastChunk,
  ) {
    if (accumulated.isEmpty || lastChunk == null) return null;
    final chunk = _toolCallChunk(
      lastChunk,
      accumulated,
      finishReason: LLMFinishReason.toolCalls,
      requireArguments: true,
    );
    accumulated.clear();
    final delta = chunk.choices.first.delta;
    if (delta.toolCalls == null && delta.invalidToolCalls == null) return null;
    return chunk;
  }

  /// Builds the chunk that closes a turn carrying [accumulated] calls, split
  /// into [GPTChunkChoiceDelta.toolCalls] and
  /// [GPTChunkChoiceDelta.invalidToolCalls] by whether their arguments decode.
  static GPTChunk _toolCallChunk(
    GPTChunk source,
    List<GPTToolCall> accumulated, {
    required LLMFinishReason finishReason,
    bool requireArguments = false,
  }) {
    final valid = <GPTToolCall>[];
    final invalid = <LLMInvalidToolCall>[];
    for (final call in accumulated) {
      final name = call.function.name;
      // A fragment that never received a name identifies no tool at all.
      if (name == null) continue;
      final error = LLMToolCall(
        id: call.id,
        name: name,
        arguments: call.function.arguments,
      ).argumentsError(requireArguments: requireArguments);
      if (error == null) {
        valid.add(call);
      } else {
        invalid.add(
          LLMInvalidToolCall(
            id: call.id,
            name: name,
            arguments: call.function.arguments,
            error: error,
          ),
        );
      }
    }
    return GPTChunk(
      id: source.id,
      created: source.created,
      model: source.model,
      systemFingerprint: source.systemFingerprint,
      choices: [
        GPTChunkChoice(
          index: 0,
          delta: GPTChunkChoiceDelta(
            role: null,
            content: null,
            toolCalls: valid.isEmpty ? null : valid,
            invalidToolCalls: invalid.isEmpty ? null : invalid,
          ),
          logProbs: null,
          finishReason: finishReason.providerName,
        ),
      ],
    );
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
