import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Parser for extracting tool calls from model output.
///
/// Supports multiple formats:
/// - JSON objects: `{"name": "tool", "arguments": {...}}`
/// - XML-wrapped: `<tool_call>{"name": "tool", ...}</tool_call>`
/// - Function-style: `tool({"arg": "value"})`
class ToolCallParser {
  /// Logger instance for this parser.
  static final LLMLogger _log = DefaultLLMLogger('llm_llamacpp.tool_parser');

  /// Parses tool calls from model output.
  ///
  /// This looks for JSON-formatted tool calls in the response.
  /// Returns an empty list if no valid tool calls are found.
  static List<LLMToolCall> parseToolCalls(String content) {
    final toolCalls = <LLMToolCall>[];
    _log.fine('parseToolCalls input: $content');

    // Try to find and parse any JSON object that looks like a tool call
    // First, try to find complete JSON objects
    final jsonObjects = _extractJsonObjects(content);
    _log.fine('Found ${jsonObjects.length} JSON objects');

    for (final jsonStr in jsonObjects) {
      _log.fine('Trying to parse JSON: $jsonStr');
      try {
        final data = json.decode(jsonStr) as Map<String, dynamic>;

        // Check if it's a tool call format
        if (data.containsKey('name')) {
          String? name;
          String? arguments;

          // Format 1: {"name": "tool", "arguments": {...}}
          if (data.containsKey('arguments')) {
            name = data['name'] as String;
            final args = data['arguments'];
            arguments = args is String ? args : json.encode(args);
          }
          // Format 2: {"name": "tool", "parameters": {...}}
          else if (data.containsKey('parameters')) {
            name = data['name'] as String;
            final args = data['parameters'];
            arguments = args is String ? args : json.encode(args);
          }
          // Format 3: {"name": "tool", "operation": "...", "a": ..., "b": ...}
          // All other keys are arguments
          else {
            name = data['name'] as String;
            final args = Map<String, dynamic>.from(data)..remove('name');
            arguments = json.encode(args);
          }

          _log.fine('Parsed tool call: name=$name, args=$arguments');
          toolCalls.add(
            LLMToolCall(
              id: 'call_${toolCalls.length}',
              name: name,
              arguments: arguments,
            ),
          );
        }
      } catch (e) {
        _log.fine('Failed to parse JSON: $e');
      }
    }

    // Try XML-like format: <tool_call>...</tool_call>
    final xmlPattern = RegExp(
      r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
      multiLine: true,
      dotAll: true,
    );

    for (final match in xmlPattern.allMatches(content)) {
      try {
        final jsonStr = match.group(1)!;
        _log.fine('Found XML-style tool call: $jsonStr');
        final data = json.decode(jsonStr) as Map<String, dynamic>;

        toolCalls.add(
          LLMToolCall(
            id: 'call_${toolCalls.length}',
            name: data['name'] as String,
            arguments: json.encode(
              data['arguments'] ?? data['parameters'] ?? {},
            ),
          ),
        );
      } catch (e) {
        _log.fine('Failed to parse XML-style tool call: $e');
      }
    }

    // Try function call format: calculator({"operation": "multiply", ...})
    final funcPattern = RegExp(
      r'(\w+)\s*\(\s*(\{[^}]+\})\s*\)',
      multiLine: true,
    );

    for (final match in funcPattern.allMatches(content)) {
      try {
        final name = match.group(1)!;
        final argsStr = match.group(2)!;
        _log.fine('Found function-style call: $name($argsStr)');

        // Verify it's valid JSON
        json.decode(argsStr);

        toolCalls.add(
          LLMToolCall(
            id: 'call_${toolCalls.length}',
            name: name,
            arguments: argsStr,
          ),
        );
      } catch (e) {
        _log.fine('Failed to parse function-style call: $e');
      }
    }

    _log.fine('Total tool calls found: ${toolCalls.length}');
    return toolCalls;
  }

  /// Extract JSON objects from a string.
  ///
  /// Returns a list of complete JSON object strings found in the content.
  static List<String> _extractJsonObjects(String content) {
    final objects = <String>[];
    var depth = 0;
    var start = -1;

    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          objects.add(content.substring(start, i + 1));
          start = -1;
        }
      }
    }

    return objects;
  }

  /// Count unbalanced braces in a string.
  ///
  /// Returns the difference between opening and closing braces.
  /// A value of 0 means braces are balanced.
  static int countBraces(String s) {
    int count = 0;
    for (final c in s.codeUnits) {
      if (c == 123) count++; // {
      if (c == 125) count--; // }
    }
    return count;
  }
}
