import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_claude/src/dto/claude_chunk.dart';
import 'package:llm_claude/src/dto/claude_usage.dart';

/// Converts Claude SSE streaming responses to [LLMChunk] streams.
///
/// Claude uses typed SSE events rather than a simple data stream:
///   event: message_start        → message metadata + input token count
///   event: content_block_start  → opens a text or tool_use block
///   event: content_block_delta  → partial content (text_delta / thinking_delta / input_json_delta)
///   event: content_block_stop   → closes the current block
///   event: message_delta        → stop_reason + output token count
///   event: message_stop         → final event (nothing useful in data)
class ClaudeStreamConverter {
  static Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    String? model,
  }) async* {
    String? eventType;
    final StringBuffer buffer = StringBuffer();

    // Accumulated state across events
    final Map<int, ClaudeToolUseBlock> toolBlocks = {};
    int? currentBlockIndex;
    int promptTokens = 0;
    int outputTokens = 0;
    ClaudeUsage? usage;
    int? cacheCreationTokens;
    int? cacheReadTokens;
    final thinkingSignatures = <int, String>{};
    String? stopReason;
    String? resolvedModel = model;

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
        continue;
      }

      if (line.startsWith('data:')) {
        buffer.write(line.substring(5).trim());
        continue;
      }

      // Empty line signals end of event
      if (line.isEmpty && buffer.isNotEmpty) {
        final dataStr = buffer.toString();
        buffer.clear();

        Map<String, dynamic> data;
        try {
          data = json.decode(dataStr) as Map<String, dynamic>;
        } catch (_) {
          eventType = null;
          continue;
        }

        switch (eventType) {
          // A mid-stream `error` event was previously unhandled, so the stream
          // ended as a *success* with truncated output and no exception. Any
          // error the API reports must surface as a thrown exception.
          case 'error':
            throw _streamError(
              data['error'] as Map<String, dynamic>? ?? const {},
              dataStr,
            );

          // Keep-alive; carries no payload.
          case 'ping':
            break;

          case 'message_start':
            final msg = data['message'] as Map<String, dynamic>?;
            if (msg != null) {
              resolvedModel = msg['model'] as String? ?? resolvedModel;
              final u = msg['usage'] as Map<String, dynamic>?;
              if (u != null) {
                promptTokens = (u['input_tokens'] as num?)?.toInt() ?? 0;
                cacheCreationTokens = (u['cache_creation_input_tokens'] as num?)
                    ?.toInt();
                cacheReadTokens = (u['cache_read_input_tokens'] as num?)
                    ?.toInt();
              }
            }

          case 'content_block_start':
            currentBlockIndex = (data['index'] as num?)?.toInt() ?? 0;
            final block = data['content_block'] as Map<String, dynamic>? ?? {};
            final type = block['type'] as String?;
            if (type == 'tool_use') {
              final toolBlock = ClaudeToolUseBlock(
                id: block['id'] as String? ?? 'tool_$currentBlockIndex',
                name: block['name'] as String? ?? '',
              );
              toolBlocks[currentBlockIndex] = toolBlock;
              // Claude names the tool in a dedicated event, before a single
              // argument byte exists, so this is the earliest a consumer can
              // possibly know which tool is running.
              yield ClaudeChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  toolCallDeltas: [
                    LLMToolCallDelta(
                      index: currentBlockIndex,
                      id: toolBlock.id,
                      name: toolBlock.name,
                    ),
                  ],
                ),
              );
            }

          case 'content_block_delta':
            final idx = (data['index'] as num?)?.toInt() ?? 0;
            final delta = data['delta'] as Map<String, dynamic>? ?? {};
            final deltaType = delta['type'] as String?;

            if (deltaType == 'text_delta') {
              final text = delta['text'] as String? ?? '';
              // Emit content chunks as they arrive
              yield ClaudeChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: text,
                  role: LLMRole.assistant,
                ),
              );
            } else if (deltaType == 'thinking_delta') {
              final thinking = delta['thinking'] as String? ?? '';
              yield ClaudeChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  thinking: thinking,
                ),
              );
            } else if (deltaType == 'signature_delta') {
              // The cryptographic signature on a thinking block. It must be
              // echoed back verbatim when continuing a conversation on the
              // same model, so it is surfaced rather than dropped.
              final signature = delta['signature'] as String? ?? '';
              thinkingSignatures[idx] =
                  (thinkingSignatures[idx] ?? '') + signature;
            } else if (deltaType == 'input_json_delta') {
              final partial = delta['partial_json'] as String? ?? '';
              if (toolBlocks.containsKey(idx)) {
                toolBlocks[idx]!.inputJson += partial;
                // The first delta of a block is routinely "". Emitting it
                // would be a second phantom "started" signal immediately
                // after the block-start delta above.
                if (partial.isNotEmpty) {
                  yield ClaudeChunk(
                    model: resolvedModel,
                    done: false,
                    createdAt: DateTime.now(),
                    message: LLMChunkMessage(
                      content: null,
                      role: LLMRole.assistant,
                      toolCallDeltas: [
                        LLMToolCallDelta(index: idx, argumentsDelta: partial),
                      ],
                    ),
                  );
                }
              }
            }

          case 'message_delta':
            final delta = data['delta'] as Map<String, dynamic>? ?? {};
            stopReason = delta['stop_reason'] as String?;
            final u = data['usage'] as Map<String, dynamic>?;
            if (u != null) {
              outputTokens = (u['output_tokens'] as num?)?.toInt() ?? 0;
              usage = ClaudeUsage(
                inputTokens: promptTokens,
                outputTokens: outputTokens,
              );
            }

            if (stopReason == 'tool_use' && toolBlocks.isNotEmpty) {
              // Emit a chunk with accumulated tool calls
              final toolCalls = toolBlocks.values
                  .map(
                    (block) => LLMToolCall(
                      id: block.id,
                      name: block.name,
                      // The accumulated wire text, verbatim. Decoding and
                      // re-encoding here did two harmful things: it normalized
                      // whitespace, so Claude was the one backend whose
                      // concatenated `toolCallDeltas` did not match the
                      // completed call byte for byte; and malformed input was
                      // swallowed into `{}`, which ran the tool with *no
                      // arguments* rather than failing. Truncated JSON is a
                      // real possibility here — a turn cut short by max_tokens,
                      // or the fine-grained tool streaming beta, which
                      // explicitly emits unvalidated partial JSON. Passing the
                      // text through lets that surface as an error at
                      // execution instead of a silent, argument-less call.
                      arguments: block.inputJson.isEmpty
                          ? '{}'
                          : block.inputJson,
                    ),
                  )
                  .toList(growable: false);

              yield ClaudeChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  toolCalls: toolCalls,
                ),
              );
            }

          case 'message_stop':
            yield ClaudeChunk(
              model: resolvedModel,
              done: true,
              createdAt: DateTime.now(),
              promptEvalCount: usage?.inputTokens ?? promptTokens,
              evalCount: usage?.outputTokens ?? outputTokens,
              usage: LLMUsage(
                promptTokens: usage?.inputTokens ?? promptTokens,
                completionTokens: usage?.outputTokens ?? outputTokens,
              ),
              finishReason: LLMFinishReason.fromProvider(stopReason),
              providerMetadata: {
                'stop_reason': ?stopReason,
                'cache_creation_input_tokens': ?cacheCreationTokens,
                'cache_read_input_tokens': ?cacheReadTokens,
                if (thinkingSignatures.isNotEmpty)
                  'thinking_signatures': Map<String, String>.fromEntries(
                    thinkingSignatures.entries.map(
                      (e) => MapEntry('${e.key}', e.value),
                    ),
                  ),
              },
              message: LLMChunkMessage(content: null, role: LLMRole.assistant),
            );
        }

        eventType = null;
      }
    }
  }

  /// Builds the exception for an in-stream `error` event.
  ///
  /// Anthropic reports the failure by `type` rather than a numeric code, but
  /// each type has a documented HTTP equivalent — an `overloaded_error` is a
  /// 529 in a non-streaming context. The status code is surfaced because retry
  /// classification works off it, so without the mapping a mid-stream overload
  /// or rate limit could never be recognized as retryable.
  static LLMApiException _streamError(
    Map<String, dynamic> error,
    String rawEvent,
  ) {
    final statusCode = switch (error['type'] as String?) {
      'invalid_request_error' => 400,
      'authentication_error' => 401,
      'permission_error' => 403,
      'not_found_error' => 404,
      'request_too_large' => 413,
      'rate_limit_error' => 429,
      'api_error' => 500,
      'overloaded_error' => 529,
      _ => null,
    };
    return LLMApiException(
      error['message'] as String? ?? 'Claude stream error',
      statusCode: statusCode,
      responseBody: rawEvent,
    );
  }
}
