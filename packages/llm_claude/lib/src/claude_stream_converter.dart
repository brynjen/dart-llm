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
          case 'message_start':
            final msg = data['message'] as Map<String, dynamic>?;
            if (msg != null) {
              resolvedModel = msg['model'] as String? ?? resolvedModel;
              final u = msg['usage'] as Map<String, dynamic>?;
              if (u != null) {
                promptTokens = (u['input_tokens'] as num?)?.toInt() ?? 0;
              }
            }

          case 'content_block_start':
            currentBlockIndex = (data['index'] as num?)?.toInt() ?? 0;
            final block = data['content_block'] as Map<String, dynamic>? ?? {};
            final type = block['type'] as String?;
            if (type == 'tool_use') {
              toolBlocks[currentBlockIndex] = ClaudeToolUseBlock(
                id: block['id'] as String? ?? 'tool_$currentBlockIndex',
                name: block['name'] as String? ?? '',
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
            } else if (deltaType == 'input_json_delta') {
              final partial = delta['partial_json'] as String? ?? '';
              if (toolBlocks.containsKey(idx)) {
                toolBlocks[idx]!.inputJson += partial;
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
                  .map((block) {
                    Map<String, dynamic> args;
                    try {
                      args = block.inputJson.isEmpty
                          ? {}
                          : json.decode(block.inputJson)
                                as Map<String, dynamic>;
                    } catch (_) {
                      args = {};
                    }
                    return LLMToolCall(
                      id: block.id,
                      name: block.name,
                      arguments: json.encode(args),
                    );
                  })
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
              message: LLMChunkMessage(content: null, role: LLMRole.assistant),
            );
        }

        eventType = null;
      }
    }
  }
}
