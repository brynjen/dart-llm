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

          if (finishReason == 'tool_calls' && toolsToCall.isNotEmpty) {
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
                    toolCalls: toolsToCall.values.toList(growable: false),
                  ),
                  logProbs: null,
                  finishReason: 'tool_calls',
                ),
              ],
            );
            yield toolCallChunk;
          } else if (finishReason != null && finishReason != 'tool_calls') {
            yield chunk;
          }
        } catch (e) {
          // Continue stream on parse errors
        }
      }
    }
  }
}
