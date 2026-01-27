import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';

/// A choice in a GPT response.
class GPTChoice {
  GPTChoice({
    required this.index,
    required this.message,
    required this.logProbs,
    required this.finishReason,
  });

  final int index;
  final GPTMessage message;
  final String? logProbs;
  final String finishReason;

  factory GPTChoice.fromJson(Map<String, dynamic> json) => GPTChoice(
    index: json['index'],
    message: GPTMessage.fromJson(json['message']),
    finishReason: json['finish_reason'],
    logProbs: json['logsProbs'],
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'message': message.toJson(),
    'logProbs': logProbs,
    'finish_reason': finishReason,
  };
}

/// A message in a GPT response.
class GPTMessage {
  GPTMessage({
    required this.role,
    required this.content,
    required this.refusal,
    required this.toolCalls,
  });

  final String role;
  final String? content;
  final String? refusal;
  final List<GPTToolCall>? toolCalls;

  factory GPTMessage.fromJson(Map<String, dynamic> json) => GPTMessage(
    role: json['role'],
    content: json['content'],
    refusal: json['refusal'],
    toolCalls: (json['tool_calls'] as List<dynamic>?)
        ?.map((e) => GPTToolCall.fromJson(e))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'refusal': refusal,
    'tool_calls': toolCalls?.map((e) => e.toJson()).toList(growable: false),
  };
}
