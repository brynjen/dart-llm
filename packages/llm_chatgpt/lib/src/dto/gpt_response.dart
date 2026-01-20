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

/// A tool call in a GPT response.
class GPTToolCall {
  GPTToolCall({
    required this.function,
    required this.index,
    this.id,
    this.type,
  });

  final String? id;
  final int index;
  final String? type;
  final GPTToolFunctionCall function;

  factory GPTToolCall.fromJson(Map<String, dynamic> json) {
    return GPTToolCall(
      id: json['id'],
      index: json['index'],
      type: json['type'],
      function: GPTToolFunctionCall.fromJson(json['function']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'type': type,
    'function': function.toJson(),
  };

  GPTToolCall copyWith({required GPTToolFunctionCall newFunction}) {
    return GPTToolCall(
      id: id,
      index: index,
      type: type,
      function: function.copyWith(
        newArguments: newFunction.arguments,
        name: newFunction.name,
      ),
    );
  }
}

/// A function call within a tool call.
class GPTToolFunctionCall {
  GPTToolFunctionCall({required this.name, this.arguments = ''});

  final String? name;
  final String arguments;

  factory GPTToolFunctionCall.fromJson(Map<String, dynamic> json) {
    return GPTToolFunctionCall(
      name: json['name'],
      arguments: json['arguments'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  GPTToolFunctionCall copyWith({required String newArguments, String? name}) {
    return GPTToolFunctionCall(
      name: name ?? this.name,
      arguments: arguments + newArguments,
    );
  }
}

/// Token usage details.
class GPTUsageTokenDetails {
  GPTUsageTokenDetails({required this.cachedTokens, required this.audioTokens});

  final int cachedTokens;
  final int audioTokens;

  factory GPTUsageTokenDetails.fromJson(Map<String, dynamic> json) =>
      GPTUsageTokenDetails(
        cachedTokens: json['cached_tokens'],
        audioTokens: json['audio_tokens'],
      );

  Map<String, dynamic> toJson() => {
    'cached_tokens': cachedTokens,
    'audio_tokens': audioTokens,
  };
}

/// Token usage statistics.
class GPTUsage {
  GPTUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.usageTokenDetails,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final GPTUsageTokenDetails? usageTokenDetails;

  factory GPTUsage.fromJson(Map<String, dynamic> json) => GPTUsage(
    promptTokens: json['prompt_tokens'],
    completionTokens: json['completion_tokens'],
    totalTokens: json['total_tokens'],
    usageTokenDetails: json['prompt_tokens_details'] != null
        ? GPTUsageTokenDetails.fromJson(json['prompt_tokens_details'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
    'prompt_tokens_details': usageTokenDetails?.toJson(),
  };
}

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
              final String arguments = toolCall.function.arguments + newArguments;
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

/// Extension to convert GPT tool calls to LLM tool calls.
extension GPTToolCallToLLMToolCallExt on List<GPTToolCall> {
  List<LLMToolCall> get toLLMToolCalls {
    List<GPTToolCall> onlyFirst = [];
    if (isNotEmpty) {
      onlyFirst = [first];
    }
    return onlyFirst
        .map(
          (call) => LLMToolCall(
            id: call.id,
            name: call.function.name!,
            arguments: call.function.arguments,
          ),
        )
        .toList(growable: false);
  }
}

/// Extension to convert GPT message to LLM message.
extension GPTMessageToLLMMessageExt on GPTMessage {
  LLMMessage get toLLMMessage {
    List<GPTToolCall>? firstToolCall;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      firstToolCall = [toolCalls!.first];
    }
    return LLMMessage(
      content: content,
      role: LLMRole.values.firstWhere((e) => e.name == role),
      toolCalls: firstToolCall?.map((e) => e.toJson()).toList(growable: false),
    );
  }
}
