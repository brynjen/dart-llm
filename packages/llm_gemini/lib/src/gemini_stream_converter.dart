import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_gemini/src/dto/gemini_chunk.dart';
import 'package:llm_gemini/src/dto/gemini_usage.dart';

/// Converts Gemini SSE streaming responses to [LLMChunk] streams.
///
/// Gemini streams SSE events where each `data:` line contains a JSON object
/// with a `candidates` array. The last chunk includes `usageMetadata`.
class GeminiStreamConverter {
  static Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    required String model,
  }) async* {
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;

      final dataStr = line.substring(5).trim();
      if (dataStr.isEmpty) continue;

      Map<String, dynamic> data;
      try {
        data = json.decode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // Check for API-level errors embedded in stream
      if (data.containsKey('error')) {
        final error = data['error'] as Map<String, dynamic>;
        final message = error['message'] as String? ?? 'Gemini API error';
        final code = (error['code'] as num?)?.toInt() ?? 500;
        throw LLMApiException(message, statusCode: code, responseBody: dataStr);
      }

      final candidates = data['candidates'] as List<dynamic>? ?? [];
      final usageMetadata = data['usageMetadata'] as Map<String, dynamic>?;

      GeminiUsage? usage;
      if (usageMetadata != null) {
        usage = GeminiUsage.fromJson(usageMetadata);
      }

      if (candidates.isEmpty) {
        if (usage != null) {
          // Final chunk with only usage info
          yield GeminiChunk(
            model: model,
            done: true,
            createdAt: DateTime.now(),
            promptEvalCount: usage.promptTokenCount,
            evalCount: usage.candidatesTokenCount,
            message: LLMChunkMessage(content: null, role: LLMRole.assistant),
          );
        }
        continue;
      }

      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final finishReason = candidate['finishReason'] as String?;
      final parts = content?['parts'] as List<dynamic>? ?? [];

      // Separate text parts and function call parts
      final textParts = <String>[];
      final functionCalls = <LLMToolCall>[];

      for (final part in parts) {
        final partMap = part as Map<String, dynamic>;
        if (partMap.containsKey('text')) {
          textParts.add(partMap['text'] as String);
        } else if (partMap.containsKey('functionCall')) {
          final fc = partMap['functionCall'] as Map<String, dynamic>;
          final name = fc['name'] as String? ?? '';
          final args = fc['args'] as Map<String, dynamic>? ?? {};
          functionCalls.add(
            LLMToolCall(
              id: 'gemini_${name}_${functionCalls.length}',
              name: name,
              arguments: json.encode(args),
            ),
          );
        }
      }

      final isDone =
          finishReason != null && finishReason != 'FINISH_REASON_UNSPECIFIED';
      final isToolCall = functionCalls.isNotEmpty;

      if (textParts.isNotEmpty) {
        final text = textParts.join();
        yield GeminiChunk(
          model: model,
          done: false,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: text, role: LLMRole.assistant),
        );
      }

      if (isToolCall) {
        yield GeminiChunk(
          model: model,
          done: false,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: null,
            role: LLMRole.assistant,
            toolCalls: functionCalls,
          ),
        );
      }

      if (isDone) {
        yield GeminiChunk(
          model: model,
          done: true,
          createdAt: DateTime.now(),
          promptEvalCount: usage?.promptTokenCount ?? 0,
          evalCount: usage?.candidatesTokenCount ?? 0,
          message: LLMChunkMessage(content: null, role: LLMRole.assistant),
        );
      }
    }
  }
}
