import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_gemini/src/dto/gemini_chunk.dart';
import 'package:llm_gemini/src/dto/gemini_usage.dart';
import 'package:llm_gemini/src/gemini_message_converter.dart';

/// Converts Gemini Interactions API SSE responses to [LLMChunk] streams.
///
/// Every `data:` line carries one JSON object discriminated by `event_type`;
/// `event: done` / `data: [DONE]` terminates the stream:
///
///   `interaction.created`   → interaction id, model, status
///   `step.start`            → opens a step (`model_output`, `thought`,
///                             `function_call`, `google_search_call`)
///   `step.delta`            → partial payload for the step at `index`:
///                             `text`, `thought_summary`, `thought_signature`,
///                             `arguments_delta`, `image`
///   `step.stop`             → cumulative `usage` plus per-step `step_usage`
///   `interaction.completed` → final status and usage
///   `error`                 → throws [LLMApiException]
///
/// Thinking is kept separate from content: `thought_summary` deltas populate
/// [LLMChunkMessage.thinking] while `text` deltas populate
/// [LLMChunkMessage.content].
class GeminiStreamConverter {
  /// Converts an Interactions SSE response into a stream of [LLMChunk]s.
  ///
  /// [model] is the requested model, used until `interaction.created` reports
  /// the model the server actually resolved.
  static Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    required String model,
  }) async* {
    var resolvedModel = model;
    String? interactionId;
    String? interactionStatus;
    GeminiUsage? usage;

    // Keyed by step index; insertion order is emission order.
    final functionCalls = <int, _GeminiFunctionCallStep>{};
    final thoughtSignatures = <int, String>{};

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        if (line.substring(6).trim() == 'done') break;
        continue;
      }
      if (!line.startsWith('data:')) continue;

      final dataStr = line.substring(5).trim();
      if (dataStr.isEmpty) continue;
      if (dataStr == '[DONE]') break;

      Map<String, dynamic> data;
      try {
        data = json.decode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      switch (data['event_type'] as String?) {
        // An error reported mid-stream must surface as a thrown exception;
        // otherwise the stream ends as a *success* with truncated output.
        case 'error':
          final error = data['error'] as Map<String, dynamic>? ?? const {};
          throw LLMApiException(
            error['message'] as String? ?? 'Gemini API error',
            statusCode: (error['code'] as num?)?.toInt(),
            responseBody: dataStr,
          );

        case 'interaction.created':
          final interaction =
              data['interaction'] as Map<String, dynamic>? ?? const {};
          interactionId = interaction['id'] as String? ?? interactionId;
          resolvedModel = interaction['model'] as String? ?? resolvedModel;
          interactionStatus =
              interaction['status'] as String? ?? interactionStatus;

        case 'step.start':
          final index = (data['index'] as num?)?.toInt() ?? 0;
          final step = data['step'] as Map<String, dynamic>? ?? const {};
          if (step['type'] == 'function_call') {
            functionCalls[index] = _GeminiFunctionCallStep(
              id: step['id'] as String?,
              name: step['name'] as String? ?? '',
              initialArguments: step['arguments'] as Map<String, dynamic>?,
            );
          }

        case 'step.delta':
          final index = (data['index'] as num?)?.toInt() ?? 0;
          final delta = data['delta'] as Map<String, dynamic>? ?? const {};
          switch (delta['type'] as String?) {
            case 'text':
              final text = delta['text'] as String? ?? '';
              if (text.isEmpty) break;
              yield GeminiChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: text,
                  role: LLMRole.assistant,
                ),
              );

            case 'thought_summary':
              final content = delta['content'] as Map<String, dynamic>?;
              final text = content?['text'] as String? ?? '';
              if (text.isEmpty) break;
              yield GeminiChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  thinking: text,
                ),
              );

            // Opaque per-step signature. It has to travel with the step it
            // belongs to on later turns, so it is accumulated and surfaced
            // rather than dropped: a missing signature is a known cause of
            // "Function call is missing a thought_signature" errors.
            case 'thought_signature':
              final signature = delta['signature'] as String? ?? '';
              if (signature.isEmpty) break;
              thoughtSignatures[index] =
                  (thoughtSignatures[index] ?? '') + signature;

            // Argument JSON arrives as fragments that only parse once
            // concatenated across every delta for the step.
            case 'arguments_delta':
              final fragment = delta['arguments'] as String? ?? '';
              functionCalls[index]?.arguments.write(fragment);

            case 'image':
              final imageData = delta['data'] as String? ?? '';
              if (imageData.isEmpty) break;
              final mimeType = delta['mime_type'] as String? ?? 'image/png';
              yield GeminiChunk(
                model: resolvedModel,
                done: false,
                createdAt: DateTime.now(),
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  images: ['data:$mimeType;base64,$imageData'],
                ),
              );
          }

        // `usage` is cumulative for the interaction; `step_usage` covers only
        // the step that just closed, so the cumulative one is kept.
        case 'step.stop':
          final stepUsage = data['usage'] as Map<String, dynamic>?;
          if (stepUsage != null) usage = GeminiUsage.fromJson(stepUsage);

        case 'interaction.completed':
          final interaction =
              data['interaction'] as Map<String, dynamic>? ?? const {};
          interactionId = interaction['id'] as String? ?? interactionId;
          interactionStatus =
              interaction['status'] as String? ?? interactionStatus;
          final completedUsage = interaction['usage'] as Map<String, dynamic>?;
          if (completedUsage != null) {
            usage = GeminiUsage.fromJson(completedUsage);
          }

          final metadata = <String, dynamic>{
            if (interactionId != null) 'interaction_id': interactionId,
            if (interactionStatus != null) 'status': interactionStatus,
            if (thoughtSignatures.isNotEmpty)
              'thought_signatures': <String, String>{
                for (final entry in thoughtSignatures.entries)
                  '${entry.key}': entry.value,
              },
            if (usage != null) ...usage.toProviderMetadata(),
          };

          if (functionCalls.isNotEmpty) {
            // The steps-based API refuses an echoed function_call unless the
            // model's thought signature is echoed with it, and LLMMessage has
            // no signature channel — so the signature rides inside the call
            // id (see GeminiMessageConverter.signatureSeparator), which
            // round-trips untouched through StreamToolExecutor. Each call
            // gets the signature accumulated at or before its step index.
            String? signatureFor(int callIndex) {
              String? best;
              for (final entry in thoughtSignatures.entries) {
                if (entry.key <= callIndex) best = entry.value;
              }
              return best;
            }

            yield GeminiChunk(
              model: resolvedModel,
              done: false,
              createdAt: DateTime.now(),
              providerMetadata: metadata,
              message: LLMChunkMessage(
                content: null,
                role: LLMRole.assistant,
                toolCalls: [
                  for (final entry in functionCalls.entries)
                    entry.value.toToolCall(
                      entry.key,
                      signature: signatureFor(entry.key),
                    ),
                ],
              ),
            );
          }

          yield GeminiChunk(
            model: resolvedModel,
            done: true,
            createdAt: DateTime.now(),
            promptEvalCount: usage?.inputTokens ?? 0,
            evalCount: usage?.outputTokens ?? 0,
            usage: usage?.toLLMUsage(),
            finishReason: _finishReason(
              interactionStatus,
              sawFunctionCalls: functionCalls.isNotEmpty,
            ),
            providerMetadata: metadata,
            message: LLMChunkMessage(content: null, role: LLMRole.assistant),
          );
      }
    }
  }

  /// Resolves the finish reason for a completed interaction.
  ///
  /// Gemini never reports a tool-call status, so a completed interaction that
  /// contained at least one `function_call` step finishes as
  /// [LLMFinishReason.toolCalls]. Otherwise the interaction `status` is
  /// normalized to a spelling [LLMFinishReason.fromProvider] understands.
  static LLMFinishReason _finishReason(
    String? status, {
    required bool sawFunctionCalls,
  }) {
    if (sawFunctionCalls) return LLMFinishReason.toolCalls;
    return LLMFinishReason.fromProvider(switch (status) {
      'completed' => 'stop',
      'incomplete' || 'max_output_tokens' => 'length',
      _ => status,
    });
  }
}

/// A `function_call` step being assembled from `arguments_delta` fragments.
class _GeminiFunctionCallStep {
  _GeminiFunctionCallStep({
    required this.id,
    required this.name,
    this.initialArguments,
  });

  /// Server-provided call id from `step.start`.
  final String? id;

  /// The function name from `step.start`.
  final String name;

  /// Arguments already present on `step.start`, used when no deltas arrive.
  final Map<String, dynamic>? initialArguments;

  /// Concatenated `arguments_delta` fragments.
  final StringBuffer arguments = StringBuffer();

  LLMToolCall toToolCall(int index, {String? signature}) {
    final raw = arguments.toString();
    Map<String, dynamic> args = initialArguments ?? const <String, dynamic>{};
    if (raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else if (decoded is Map) {
          args = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Keep whatever `step.start` provided when the fragments do not form
        // valid JSON.
      }
    }
    final callId = (id != null && id!.isNotEmpty) ? id! : 'gemini_call_$index';
    return LLMToolCall(
      id: signature == null || signature.isEmpty
          ? callId
          : '$callId${GeminiMessageConverter.signatureSeparator}$signature',
      name: name,
      arguments: json.encode(args),
    );
  }
}
