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
