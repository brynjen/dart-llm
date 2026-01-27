import 'package:llm_chatgpt/src/dto/gpt_choice.dart';
import 'package:llm_chatgpt/src/dto/gpt_extensions.dart';
import 'package:llm_chatgpt/src/dto/gpt_usage.dart';
import 'package:llm_core/llm_core.dart';

/// Response from OpenAI chat completions endpoint.
class GPTResponse extends LLMResponse {
  GPTResponse({
    required this.id,
    required this.created,
    required super.model,
    required this.choices,
    required this.usage,
    required this.systemFingerprint,
  }) : super(
         createdAt: created,
         role: choices[0].message.role,
         content: choices[0].message.content,
         done: true,
         doneReason: choices[0].finishReason,
         promptEvalCount: usage.promptTokens,
         evalCount: usage.completionTokens,
         toolCalls: choices[0].message.toolCalls?.toLLMToolCalls,
       );

  final String id;
  final String object = 'chat.completion';
  final DateTime created;
  final List<GPTChoice> choices;
  final GPTUsage usage;
  final String? systemFingerprint;

  factory GPTResponse.fromJson(Map<String, dynamic> json) {
    return GPTResponse(
      id: json['id'],
      created: DateTime.fromMillisecondsSinceEpoch(json['created'] * 1000),
      model: json['model'],
      choices: (json['choices'] as List<dynamic>)
          .map((choiceJson) => GPTChoice.fromJson(choiceJson))
          .toList(growable: false),
      usage: GPTUsage.fromJson(json['usage']),
      systemFingerprint: json['system_fingerprint'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    'created': created.millisecondsSinceEpoch / 1000,
    'model': model,
    'choices': choices.map((choice) => choice.toJson()).toList(growable: false),
    'usage': usage.toJson(),
    'system_fingerprint': systemFingerprint,
  };
}
