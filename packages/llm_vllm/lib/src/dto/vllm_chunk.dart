import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/dto/vllm_extensions.dart';
import 'package:llm_vllm/src/dto/vllm_tool_call.dart';
import 'package:llm_vllm/src/dto/vllm_usage.dart';

/// Streaming chunk from a vLLM OpenAI-compatible chat completion.
class VLLMChunk extends LLMChunk {
  VLLMChunk({
    required this.id,
    required this.created,
    required super.model,
    required this.choices,
    required this.systemFingerprint,
    this.vllmUsage,
  }) : super(
         createdAt: created,
         done: choices.isEmpty
             ? vllmUsage != null
             : choices[0].finishReason != null,
         finishReason: choices.isNotEmpty && choices[0].finishReason != null
             ? LLMFinishReason.fromProvider(choices[0].finishReason)
             : null,
         promptEvalCount: vllmUsage?.promptTokens,
         evalCount: vllmUsage?.completionTokens,
         usage: vllmUsage != null
             ? LLMUsage(
                 promptTokens: vllmUsage.promptTokens,
                 completionTokens: vllmUsage.completionTokens,
                 totalTokens: vllmUsage.totalTokens,
                 reasoningTokens: vllmUsage.reasoningTokens,
               )
             : null,
         providerMetadata: {
           'id': id,
           if (systemFingerprint != null)
             'system_fingerprint': systemFingerprint,
         },
         message: choices.isEmpty
             ? null
             : LLMChunkMessage(
                 content: choices[0].delta.content,
                 thinking: choices[0].delta.thinking,
                 // vLLM (like OpenAI) sends `role` only on the first delta of
                 // a choice; later content deltas omit it. Every delta in a
                 // completion choice is assistant output, so a delta that
                 // carries anything defaults to assistant — a null role here
                 // makes `chatResponse` skip the chunk when folding, which
                 // against a live server dropped all content after the first
                 // (empty) delta.
                 role: choices[0].delta.role != null
                     ? LLMRole.values.firstWhere(
                         (e) => e.name == choices[0].delta.role,
                         orElse: () => LLMRole.assistant,
                       )
                     : choices[0].finishReason != null ||
                           choices[0].delta.content != null ||
                           choices[0].delta.thinking != null ||
                           choices[0].delta.toolCalls != null
                     ? LLMRole.assistant
                     : null,
                 toolCalls: choices[0].delta.toolCalls?.toLLMToolCalls,
               ),
       );

  final String id;
  final DateTime created;
  final List<VLLMChunkChoice> choices;
  final String? systemFingerprint;
  final VLLMUsage? vllmUsage;

  factory VLLMChunk.fromJson(Map<String, dynamic> json) {
    return VLLMChunk(
      id: json['id'] as String? ?? '',
      created: _createdAt(json['created']),
      model: json['model'] as String?,
      systemFingerprint: json['system_fingerprint'] as String?,
      choices: (json['choices'] as List<dynamic>? ?? const [])
          .map((choice) => VLLMChunkChoice.fromJson(choice))
          .toList(growable: false),
      vllmUsage: json['usage'] != null
          ? VLLMUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
    );
  }

  static DateTime _createdAt(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    return DateTime.now();
  }
}

/// A choice in a vLLM streaming chunk.
class VLLMChunkChoice {
  VLLMChunkChoice({
    required this.index,
    required this.delta,
    required this.logProbs,
    required this.finishReason,
  });

  final int index;
  final VLLMChunkChoiceDelta delta;
  final Object? logProbs;
  final String? finishReason;

  factory VLLMChunkChoice.fromJson(Map<String, dynamic> json) =>
      VLLMChunkChoice(
        index: json['index'] as int? ?? 0,
        delta: VLLMChunkChoiceDelta.fromJson(
          json['delta'] as Map<String, dynamic>? ?? const {},
        ),
        logProbs: json['logprobs'] ?? json['logProbs'],
        finishReason: json['finish_reason'] as String?,
      );
}

/// Delta content in a vLLM streaming chunk.
class VLLMChunkChoiceDelta {
  VLLMChunkChoiceDelta({
    required this.role,
    required this.content,
    required this.thinking,
    required this.toolCalls,
  });

  final String? role;
  final String? content;
  final String? thinking;
  final List<VLLMToolCall>? toolCalls;

  factory VLLMChunkChoiceDelta.fromJson(Map<String, dynamic> json) =>
      VLLMChunkChoiceDelta(
        role: json['role'] as String?,
        content: json['content'] as String?,
        thinking:
            json['reasoning_content'] as String? ??
            json['reasoning'] as String? ??
            json['thinking'] as String?,
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((call) => VLLMToolCall.fromJson(call))
            .toList(growable: false),
      );
}
