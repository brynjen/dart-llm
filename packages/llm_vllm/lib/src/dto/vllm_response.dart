import 'package:llm_vllm/src/dto/vllm_choice.dart';
import 'package:llm_vllm/src/dto/vllm_extensions.dart';
import 'package:llm_vllm/src/dto/vllm_usage.dart';
import 'package:llm_core/llm_core.dart';

/// Response from vLLM chat completions endpoint.
class VLLMResponse extends LLMResponse {
  VLLMResponse({
    required this.id,
    required this.created,
    required super.model,
    required this.choices,
    required VLLMUsage usage,
    required this.systemFingerprint,
  }) : vllmUsage = usage,
       super(
         createdAt: created,
         role: choices[0].message.role,
         content: choices[0].message.content,
         done: true,
         doneReason: choices[0].finishReason,
         promptEvalCount: usage.promptTokens,
         evalCount: usage.completionTokens,
         usage: LLMUsage(
           promptTokens: usage.promptTokens,
           completionTokens: usage.completionTokens,
           totalTokens: usage.totalTokens,
         ),
         providerMetadata: {
           'id': id,
           if (systemFingerprint != null)
             'system_fingerprint': systemFingerprint,
         },
         toolCalls: choices[0].message.toolCalls?.toLLMToolCalls,
       );

  final String id;
  final String object = 'chat.completion';
  final DateTime created;
  final List<VLLMChoice> choices;
  final VLLMUsage vllmUsage;
  final String? systemFingerprint;

  factory VLLMResponse.fromJson(Map<String, dynamic> json) {
    return VLLMResponse(
      id: json['id'] as String? ?? '',
      created: DateTime.fromMillisecondsSinceEpoch(
        (json['created'] as int? ?? 0) * 1000,
      ),
      model: json['model'] as String? ?? '',
      choices: (json['choices'] as List<dynamic>? ?? const [])
          .map(
            (choiceJson) =>
                VLLMChoice.fromJson(choiceJson as Map<String, dynamic>),
          )
          .toList(growable: false),
      usage: VLLMUsage.fromJson(
        json['usage'] as Map<String, dynamic>? ?? const {},
      ),
      systemFingerprint: json['system_fingerprint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    'created': created.millisecondsSinceEpoch / 1000,
    'model': model,
    'choices': choices.map((choice) => choice.toJson()).toList(growable: false),
    'usage': vllmUsage.toJson(),
    'system_fingerprint': systemFingerprint,
  };
}
