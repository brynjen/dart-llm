import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';
import 'package:llm_core/llm_core.dart';

/// Streaming chunk from OpenAI.
class GPTChunk extends LLMChunk {
  GPTChunk({
    required this.id,
    required this.created,
    required super.model,
    required this.systemFingerprint,
    required this.choices,
  }) : super(
         createdAt: created,
         done: choices[0].finishReason != null,
         message: LLMChunkMessage(
           content: choices[0].delta.content,
           role: choices[0].delta.role != null
               ? LLMRole.values.firstWhere(
                   (e) => e.name == choices[0].delta.role,
                 )
               : null,
           toolCalls: choices[0].delta.toolCalls
               ?.where((call) => call.function.name != null)
               .map(
                 (call) => LLMToolCall(
                   id: call.id,
                   name: call.function.name!,
                   arguments: call.function.arguments,
                 ),
               )
               .toList(growable: false),
         ),
       );

  final String id;
  final String object = 'chat.completion.chunk';
  final DateTime created;
  final String? systemFingerprint;
  final List<GPTChunkChoice> choices;

  factory GPTChunk.fromJson(Map<String, dynamic> json) => GPTChunk(
    id: json['id'],
    created: DateTime.fromMillisecondsSinceEpoch(json['created'] * 1000),
    model: json['model'],
    systemFingerprint: json['system_fingerprint'],
    choices: (json['choices'] as List<dynamic>)
        .map((choice) => GPTChunkChoice.fromJson(choice))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created': created.millisecondsSinceEpoch / 1000,
    'model': model,
    'object': object,
    'choices': choices.map((e) => e.toJson()).toList(growable: false),
    'system_fingerprint': systemFingerprint,
  };

  GPTChunk copyWith({required GPTChunk newChunk}) {
    return GPTChunk(
      id: id,
      created: created,
      model: model,
      systemFingerprint: systemFingerprint,
      choices: choices.map((choice) {
        return GPTChunkChoice(
          index: choice.index,
          delta: GPTChunkChoiceDelta(
            role: choice.delta.role,
            content: choice.delta.content,
            toolCalls: choice.delta.toolCalls?.map((toolCall) {
              final newArguments =
                  newChunk.choices[0].delta.toolCalls?[0].function.arguments ??
                  '';
              final String arguments =
                  toolCall.function.arguments + newArguments;
              return GPTToolCall(
                id: toolCall.id,
                index: toolCall.index,
                type: 'function',
                function: GPTToolFunctionCall(
                  name:
                      toolCall.function.name ??
                      newChunk.choices[0].delta.toolCalls?[0].function.name,
                  arguments: arguments,
                ),
              );
            }).toList(),
          ),
          logProbs: choice.logProbs,
          finishReason: choice.finishReason,
        );
      }).toList(),
    );
  }
}

/// A choice in a streaming chunk.
class GPTChunkChoice {
  GPTChunkChoice({
    required this.index,
    required this.delta,
    required this.logProbs,
    required this.finishReason,
  });

  final int index;
  final GPTChunkChoiceDelta delta;
  final String? logProbs;
  final String? finishReason;

  factory GPTChunkChoice.fromJson(Map<String, dynamic> json) => GPTChunkChoice(
    index: json['index'],
    delta: GPTChunkChoiceDelta.fromJson(json['delta']),
    logProbs: json['logProbs'],
    finishReason: json['finish_reason'],
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'delta': delta.toJson(),
    'logProbs': logProbs,
    'finish_reason': finishReason,
  };
}

/// Delta content in a streaming chunk.
class GPTChunkChoiceDelta {
  GPTChunkChoiceDelta({
    required this.role,
    required this.content,
    required this.toolCalls,
  });

  final String? role;
  final String? content;
  final List<GPTToolCall>? toolCalls;

  factory GPTChunkChoiceDelta.fromJson(Map<String, dynamic> json) =>
      GPTChunkChoiceDelta(
        role: json['role'],
        content: json['content'],
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((e) => GPTToolCall.fromJson(e))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (role != null) {
      map['role'] = role;
    }
    if (content != null) {
      map['content'] = content;
    }
    if (toolCalls != null) {
      map['tool_calls'] = toolCalls
          ?.map((e) => e.toJson())
          .toList(growable: false);
    }
    return map;
  }
}
