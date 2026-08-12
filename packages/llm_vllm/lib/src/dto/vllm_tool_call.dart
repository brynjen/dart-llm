/// A tool call in a VLLM response.
class VLLMToolCall {
  VLLMToolCall({
    required this.function,
    required this.index,
    this.id,
    this.type,
  });

  final String? id;
  final int index;
  final String? type;
  final VLLMToolFunctionCall function;

  factory VLLMToolCall.fromJson(Map<String, dynamic> json) {
    return VLLMToolCall(
      id: json['id'] as String?,
      index: json['index'] as int? ?? 0,
      type: json['type'] as String?,
      function: VLLMToolFunctionCall.fromJson(
        json['function'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'type': type,
    'function': function.toJson(),
  };

  VLLMToolCall copyWith({required VLLMToolFunctionCall newFunction}) {
    return VLLMToolCall(
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
class VLLMToolFunctionCall {
  VLLMToolFunctionCall({required this.name, this.arguments = ''});

  final String? name;
  final String arguments;

  factory VLLMToolFunctionCall.fromJson(Map<String, dynamic> json) {
    return VLLMToolFunctionCall(
      name: json['name'] as String?,
      arguments: json['arguments'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  VLLMToolFunctionCall copyWith({required String newArguments, String? name}) {
    return VLLMToolFunctionCall(
      name: name ?? this.name,
      arguments: arguments + newArguments,
    );
  }
}
