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
    // Whether this turn actually handed executable calls to the caller, which
    // is what the terminal chunk's finish reason has to agree with.
    var emittedToolCalls = false;
    int? currentBlockIndex;
    int promptTokens = 0;
    int outputTokens = 0;
    ClaudeUsage? usage;
    int? cacheCreationTokens;
    int? cacheReadTokens;
    final thinkingSignatures = <int, String>{};
    String? stopReason;
    String? resolvedModel = model;

    try {
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
                  cacheCreationTokens =
                      (u['cache_creation_input_tokens'] as num?)?.toInt();
                  cacheReadTokens = (u['cache_read_input_tokens'] as num?)
                      ?.toInt();
                }
              }

            case 'content_block_start':
              currentBlockIndex = (data['index'] as num?)?.toInt() ?? 0;
              final block =
                  data['content_block'] as Map<String, dynamic>? ?? {};
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

              // Claude usually spells a tool-calling turn `tool_use`, but not
              // always — a turn mixing text and tool blocks can end `end_turn`.
              // Per the OpenAI specification the finish reason is `tool_calls`
              // "if the model called a tool", so the classification follows the
              // blocks rather than the spelling. `max_tokens` stays a truncation
              // but its blocks are still surfaced, split by whether their input
              // decodes — the shape OpenAI, LangChain and the Vercel AI SDK
              // give a truncated turn. Only a refusal withholds them: the
              // provider did not stand behind the calls.
              final reported = LLMFinishReason.fromProvider(stopReason);
              final surfacesToolCalls =
                  toolBlocks.isNotEmpty &&
                  (reported.canBecomeToolCalls ||
                      reported == LLMFinishReason.length);

              if (surfacesToolCalls) {
                final split = LLMToolCall.partition(
                  toolBlocks.values.map(
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
                      // explicitly emits unvalidated partial JSON — and lands
                      // in `invalidToolCalls` instead.
                      arguments: block.inputJson.isEmpty
                          ? '{}'
                          : block.inputJson,
                    ),
                  ),
                );
                emittedToolCalls = true;

                yield ClaudeChunk(
                  model: resolvedModel,
                  done: false,
                  createdAt: DateTime.now(),
                  message: LLMChunkMessage(
                    content: null,
                    role: LLMRole.assistant,
                    toolCalls: split.valid.isEmpty ? null : split.valid,
                    invalidToolCalls: split.invalid.isEmpty
                        ? null
                        : split.invalid,
                  ),
                );
              }

            case 'message_stop':
              // Anthropic's `input_tokens` counts only the tokens *after* the
              // last cache breakpoint: per its own documentation,
              // `total_input_tokens = cache_read_input_tokens +
              // cache_creation_input_tokens + input_tokens`. Reporting it
              // unchanged made `promptTokens` — and therefore the derived
              // `totalTokens` — under-count every cached request, and broke the
              // contract that `LLMUsage.cachedTokens` is a *subset* of
              // `promptTokens`, which holds on every other provider. The raw
              // fields stay available on `providerMetadata` below.
              final totalPromptTokens =
                  (usage?.inputTokens ?? promptTokens) +
                  (cacheReadTokens ?? 0) +
                  (cacheCreationTokens ?? 0);
              yield ClaudeChunk(
                model: resolvedModel,
                done: true,
                createdAt: DateTime.now(),
                promptEvalCount: totalPromptTokens,
                evalCount: usage?.outputTokens ?? outputTokens,
                usage: LLMUsage(
                  promptTokens: totalPromptTokens,
                  completionTokens: usage?.outputTokens ?? outputTokens,
                  cachedTokens: cacheReadTokens,
                  cacheWriteTokens: cacheCreationTokens,
                ),
                finishReason: LLMFinishReason.resolve(
                  reported: LLMFinishReason.fromProvider(stopReason),
                  hasCompleteToolCalls: emittedToolCalls,
                ),
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
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                ),
              );
          }

          eventType = null;
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
