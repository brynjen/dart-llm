import 'llm_tool_param.dart';

/// Abstract base class for LLM tools (function calling).
///
/// Implement this class to create tools that can be invoked by LLMs.
///
/// Example:
/// ```dart
/// class CalculatorTool extends LLMTool {
///   @override
///   String get name => 'calculator';
///
///   @override
///   String get description => 'Performs basic arithmetic operations';
///
///   @override
///   List<LLMToolParam> get parameters => [
///     LLMToolParam(
///       name: 'expression',
///       type: 'string',
///       description: 'The arithmetic expression to evaluate',
///       isRequired: true,
///     ),
///   ];
///
///   @override
///   Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
///     final expression = args['expression'] as String;
///     // ... evaluate expression ...
///     return result.toString();
///   }
/// }
/// ```
abstract class LLMTool {
  /// The name of the tool, used to match up with the function call.
  String get name;

  /// A description of what the tool does.
  String get description;

  /// Parameters the tool accepts.
  List<LLMToolParam> get parameters;

  /// Description that can be added to the system message to help the LLM understand the tool.
  String get llmDescription => '''- $name: $description''';

  /// Executes the tool with the given arguments.
  ///
  /// [args] contains the parsed JSON arguments from the LLM.
  /// [extra] can be used to pass additional context (e.g., user session).
  ///
  /// Returns the result as a string to be sent back to the LLM.
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra});

  /// Converts this tool to a JSON schema suitable for API requests.
  Map<String, dynamic> get toJson {
    final props = {for (final p in parameters) p.name: p.toJsonSchema()};
    final reqs = [
      for (final p in parameters)
        if (p.isRequired) p.name,
    ];

    return {
      "type": "function",
      "function": {
        "name": name,
        "description": description,
        if (parameters.isNotEmpty)
          "parameters": {
            "type": "object",
            "properties": props,
            if (reqs.isNotEmpty) "required": reqs,
          },
      },
    };
  }
}
