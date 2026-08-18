import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/tool_calls/pythonic_arguments.dart';
import 'package:llm_llamacpp/src/tool_calls/tool_call_syntax.dart';

/// Parser for extracting tool calls from raw model output.
///
/// Running a model locally means llama.cpp hands us detokenized text and nothing
/// else, so tool calls have to be recovered from that text. See [ToolCallFormat]
/// for the families handled.
///
/// The strategy is delimiter-first: when the output contains a known opening
/// delimiter, only that family's payload grammar is applied. Bare JSON and bare
/// Pythonic calls are tried only when no delimiter was present. That ordering is
/// about correctness, not just speed — running every pass across the whole output
/// made a single `<tool_call>{...}</tool_call>` yield the same call twice.
class ToolCallParser {
  /// Logger instance for this parser.
  static final LLMLogger _log = DefaultLLMLogger('llm_llamacpp.tool_parser');

  /// Parses tool calls from model output.
  ///
  /// [format] pins the expected family when it is known from the model's chat
  /// template. It is a hint, not a constraint: a model can emit its native
  /// format regardless of what the prompt asked for, so detection still runs and
  /// takes precedence when it finds a delimiter.
  ///
  /// Returns an empty list when no tool calls are found.
  static List<LLMToolCall> parseToolCalls(
    String content, {
    ToolCallFormat? format,
  }) {
    _log.fine('parseToolCalls input: $content');

    final detected = ToolCallFormat.detectFromContent(content) ?? format;
    _log.fine('Tool-call format: ${detected?.name ?? 'none'}');

    final calls = switch (detected) {
      null => _parseBare(content),
      ToolCallFormat.json => _parseBare(content),
      ToolCallFormat.pythonic => _parsePythonic(content, lenient: false),
      final f => _parseDelimited(content, f),
    };

    final deduped = _dedupe(calls);
    _log.fine('Total tool calls found: ${deduped.length}');
    return deduped;
  }

  /// Extracts and parses every delimited segment for [format].
  static List<LLMToolCall> _parseDelimited(
    String content,
    ToolCallFormat format,
  ) {
    final (open, close) = format.delimiters!;
    final calls = <LLMToolCall>[];

    var searchFrom = 0;
    while (searchFrom < content.length) {
      final start = content.indexOf(open, searchFrom);
      if (start < 0) break;
      final payloadStart = start + open.length;

      final int payloadEnd;
      if (close.isEmpty) {
        // Openers with no closing delimiter (Mistral, python_tag) run to the end
        // of the output.
        payloadEnd = content.length;
      } else {
        final found = content.indexOf(close, payloadStart);
        // No closing delimiter yet: the model is still mid-call, or stopped
        // early. Parse what we have — every payload grammar rejects incomplete
        // input, so a truncated call yields nothing rather than something wrong.
        payloadEnd = found < 0 ? content.length : found;
      }

      final payload = content.substring(payloadStart, payloadEnd).trim();
      calls.addAll(_parsePayload(payload, format));

      searchFrom = close.isEmpty ? content.length : payloadEnd + close.length;
    }

    return calls;
  }

  static List<LLMToolCall> _parsePayload(
    String payload,
    ToolCallFormat format,
  ) {
    if (payload.isEmpty) return const [];

    // Inside an explicit delimiter we already know the model meant to call a
    // tool, so malformed-but-recoverable syntax is worth salvaging. Outside one,
    // leniency would invent calls out of prose.
    if (format.isPythonic) return _parsePythonic(payload, lenient: true);
    return _parseJson(payload);
  }

  static List<LLMToolCall> _parsePythonic(
    String payload, {
    required bool lenient,
  }) {
    final parsed = parsePythonicCallList(payload, lenient: lenient);
    return [
      for (final call in parsed)
        LLMToolCall(id: '', name: call.name, arguments: call.argumentsJson),
    ];
  }

  /// Parses a JSON payload that is either one call object or an array of them.
  static List<LLMToolCall> _parseJson(String payload) {
    final calls = <LLMToolCall>[];

    for (final chunk in _extractJsonValues(payload)) {
      final dynamic decoded;
      try {
        decoded = json.decode(chunk);
      } catch (e) {
        _log.fine('Failed to parse JSON payload: $e');
        continue;
      }
      calls.addAll(_callsFromJson(decoded));
    }

    return calls;
  }

  static List<LLMToolCall> _callsFromJson(dynamic decoded) {
    if (decoded is List) {
      return [for (final entry in decoded) ..._callsFromJson(entry)];
    }
    if (decoded is! Map<String, dynamic>) return const [];

    // OpenAI-shaped: {"type": "function", "function": {"name", "arguments"}}
    final nested = decoded['function'];
    if (nested is Map<String, dynamic>) return _callsFromJson(nested);

    // `tool_name` is Cohere's spelling; the rest use `name`.
    const nameKeys = ['name', 'tool_name'];
    final nameKey = nameKeys.firstWhere(
      (k) => decoded[k] is String,
      orElse: () => '',
    );
    if (nameKey.isEmpty) return const [];
    final name = decoded[nameKey] as String;

    final rawArgs =
        decoded['arguments'] ?? decoded['parameters'] ?? decoded['args'];
    final String arguments;
    if (rawArgs == null) {
      // Flat shape: every key other than the name is an argument.
      final flat = Map<String, dynamic>.from(decoded)..remove(nameKey);
      arguments = json.encode(flat);
    } else if (rawArgs is String) {
      // Some models double-encode the arguments object.
      arguments = rawArgs;
    } else {
      arguments = json.encode(rawArgs);
    }

    return [LLMToolCall(id: '', name: name, arguments: arguments)];
  }

  /// `name({"arg": 1})` — a function call whose single argument is a JSON object.
  ///
  /// Emitted by models prompted with a "call the tool like this" example. Checked
  /// before the plain-JSON pass so the argument object is attributed to its
  /// function rather than scanned as a standalone call.
  static List<LLMToolCall> _parseFunctionStyle(String content) {
    final calls = <LLMToolCall>[];
    final pattern = RegExp(r'([A-Za-z_][\w.\-]*)\s*\(\s*\{');
    for (final match in pattern.allMatches(content)) {
      final name = match.group(1)!;
      // The match ends just past the `{`, so that brace starts the argument
      // object. Scanning from there keeps nested objects intact.
      final objects = _extractJsonValues(content.substring(match.end - 1));
      if (objects.isEmpty) continue;
      try {
        final decoded = json.decode(objects.first);
        if (decoded is! Map<String, dynamic>) continue;
        // A JSON tool call that merely happens to follow an identifier is not a
        // function-style call; leave it to the JSON pass.
        if (decoded.containsKey('name') || decoded.containsKey('tool_name')) {
          continue;
        }
        calls.add(
          LLMToolCall(id: '', name: name, arguments: json.encode(decoded)),
        );
      } catch (_) {
        // Not JSON after all.
      }
    }
    return calls;
  }

  /// Fallback for output with no recognizable delimiter.
  static List<LLMToolCall> _parseBare(String content) {
    final functionCalls = _parseFunctionStyle(content);
    if (functionCalls.isNotEmpty) return functionCalls;

    final jsonCalls = _parseJson(content);
    if (jsonCalls.isNotEmpty) return jsonCalls;

    // A bare Pythonic list, e.g. from a model whose python tag was stripped.
    final start = content.indexOf('[');
    final end = content.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return _parsePythonic(content.substring(start, end + 1), lenient: false);
    }
    return const [];
  }

  /// Drops repeats and assigns stable ids.
  ///
  /// Ids are assigned here rather than at construction so a call found twice
  /// collapses into one instead of becoming `call_0` and `call_1`.
  static List<LLMToolCall> _dedupe(List<LLMToolCall> calls) {
    final seen = <String>{};
    final result = <LLMToolCall>[];
    for (final call in calls) {
      if (call.name.isEmpty) continue;
      if (!seen.add('${call.name} ${call.arguments}')) continue;
      result.add(
        LLMToolCall(
          id: 'call_${result.length}',
          name: call.name,
          arguments: call.arguments,
        ),
      );
    }
    return result;
  }

  /// Extracts complete top-level JSON objects and arrays from [content].
  ///
  /// The scan is string-aware, so braces and brackets inside a JSON string value
  /// cannot unbalance it.
  static List<String> _extractJsonValues(String content) {
    final values = <String>[];
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var i = 0; i < content.length; i++) {
      final c = content[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }

      switch (c) {
        case '"':
          inString = true;
        case '{':
        case '[':
          if (depth == 0) start = i;
          depth++;
        case '}':
        case ']':
          if (depth > 0) {
            depth--;
            if (depth == 0 && start >= 0) {
              values.add(content.substring(start, i + 1));
              start = -1;
            }
          }
      }
    }

    return values;
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
