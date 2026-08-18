import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';
import 'package:llm_chatgpt/src/dto/gpt_usage.dart';
import 'package:llm_core/llm_core.dart';

/// Streaming chunk from OpenAI.
///
/// With `stream_options: {include_usage: true}` OpenAI ends the stream with a
/// frame whose `choices` is empty and that carries only `usage`, so the chunk
/// must tolerate an empty choice list.
class GPTChunk extends LLMChunk {
  GPTChunk({
    required this.id,
    required this.created,
    required super.model,
    required this.systemFingerprint,
    required this.choices,
    this.gptUsage,
  }) : super(
         createdAt: created,
         done: choices.isEmpty
             ? gptUsage != null
             : choices[0].finishReason != null,
         finishReason: choices.isNotEmpty && choices[0].finishReason != null
             ? LLMFinishReason.fromProvider(choices[0].finishReason)
             : null,
         promptEvalCount: gptUsage?.promptTokens,
         evalCount: gptUsage?.completionTokens,
         usage: gptUsage != null
             ? LLMUsage(
                 promptTokens: gptUsage.promptTokens,
                 completionTokens: gptUsage.completionTokens,
                 totalTokens: gptUsage.totalTokens,
                 reasoningTokens: gptUsage.reasoningTokens,
               )
             : null,
         providerMetadata: {'id': id, 'system_fingerprint': ?systemFingerprint},
         message: choices.isEmpty
             ? null
             : LLMChunkMessage(
                 content: choices[0].delta.content,
                 thinking: choices[0].delta.thinking,
                 // OpenAI sends `role` only on the first delta of a choice;
                 // later content deltas and the finish chunk omit it. A null
                 // role makes `chatResponse` skip the chunk when folding and
                 // breaks the tool loop's final-answer detection, so any
                 // delta that carries something defaults to assistant (same
                 // fix as VLLMChunk).
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
  final GPTUsage? gptUsage;

  factory GPTChunk.fromJson(Map<String, dynamic> json) => GPTChunk(
    id: json['id'],
    created: DateTime.fromMillisecondsSinceEpoch(json['created'] * 1000),
    model: json['model'],
    systemFingerprint: json['system_fingerprint'],
    choices: (json['choices'] as List<dynamic>? ?? const [])
        .map((choice) => GPTChunkChoice.fromJson(choice))
        .toList(growable: false),
    gptUsage: json['usage'] != null
        ? GPTUsage.fromJson(json['usage'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created': created.millisecondsSinceEpoch / 1000,
    'model': model,
    'object': object,
    'choices': choices.map((e) => e.toJson()).toList(growable: false),
    'system_fingerprint': systemFingerprint,
    if (gptUsage != null) 'usage': gptUsage!.toJson(),
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
    this.thinking,
  });

  final String? role;
  final String? content;
  final List<GPTToolCall>? toolCalls;

  /// Reasoning delta from OpenAI-compatible servers.
  ///
  /// OpenAI itself never streams raw reasoning on chat completions, but
  /// compatible servers (vLLM, Ollama, OpenRouter) emit it as
  /// `reasoning_content` or `reasoning`.
  final String? thinking;

  factory GPTChunkChoiceDelta.fromJson(Map<String, dynamic> json) =>
      GPTChunkChoiceDelta(
        role: json['role'],
        content: json['content'],
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((e) => GPTToolCall.fromJson(e))
            .toList(growable: false),
        thinking: (json['reasoning_content'] ?? json['reasoning']) as String?,
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
    if (thinking != null) {
      map['reasoning_content'] = thinking;
    }
    return map;
  }
}
