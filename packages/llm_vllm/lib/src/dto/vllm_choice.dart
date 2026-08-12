import 'package:llm_vllm/src/dto/vllm_tool_call.dart';

/// A choice in a VLLM response.
class VLLMChoice {
  VLLMChoice({
    required this.index,
    required this.message,
    required this.logProbs,
    required this.finishReason,
  });

  final int index;
  final VLLMMessage message;
  final Object? logProbs;
  final String finishReason;

  factory VLLMChoice.fromJson(Map<String, dynamic> json) => VLLMChoice(
    index: json['index'] as int? ?? 0,
    message: VLLMMessage.fromJson(
      json['message'] as Map<String, dynamic>? ?? const {},
    ),
    finishReason: json['finish_reason'] as String? ?? 'stop',
    logProbs: json['logprobs'] ?? json['logsProbs'],
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'message': message.toJson(),
    'logProbs': logProbs,
    'finish_reason': finishReason,
  };
}

/// A message in a VLLM response.
class VLLMMessage {
  VLLMMessage({
    required this.role,
    required this.content,
    required this.refusal,
    required this.toolCalls,
  });

  final String role;
  final String? content;
  final String? refusal;
  final List<VLLMToolCall>? toolCalls;

  factory VLLMMessage.fromJson(Map<String, dynamic> json) => VLLMMessage(
    role: json['role'] as String? ?? 'assistant',
    content: json['content'] as String?,
    refusal: json['refusal'] as String?,
    toolCalls: (json['tool_calls'] as List<dynamic>?)
        ?.map((e) => VLLMToolCall.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'refusal': refusal,
    'tool_calls': toolCalls?.map((e) => e.toJson()).toList(growable: false),
  };
}
