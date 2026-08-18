library;

import 'dart:convert';

import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/tool_calls/tool_call_syntax.dart';
import 'package:llm_llamacpp/src/tool_definition_injector.dart';
import 'package:test/test.dart';

/// A minimal OpenAI-style function schema, as `LLMTool.toJson['function']` gives.
const calculatorSchema = {
  'name': 'calculator',
  'description': 'Performs basic math operations',
  'parameters': {
    'type': 'object',
    'properties': {
      'operation': {'type': 'string', 'description': 'add|multiply'},
      'a': {'type': 'number', 'description': 'first operand'},
      'b': {'type': 'number', 'description': 'second operand'},
    },
    'required': ['operation', 'a', 'b'],
  },
};

final schemas = [json.encode(calculatorSchema)];

void main() {
  group('injectToolDefinitions', () {
    test('returns the same list when there are no tools', () {
      final messages = [IsolateMessage(role: 'user', content: 'hi')];

      final result = injectToolDefinitions(
        messages,
        const [],
        format: ToolCallFormat.lfm2,
      );

      expect(identical(messages, result), isTrue);
    });

    test('appends to an existing system message for LFM2', () {
      final result = injectToolDefinitions(
        [
          IsolateMessage(role: 'system', content: 'You are helpful.'),
          IsolateMessage(role: 'user', content: 'What is 2+2?'),
        ],
        schemas,
        format: ToolCallFormat.lfm2,
      );

      expect(result, hasLength(2));
      expect(result[0].role, 'system');
      expect(result[0].content, startsWith('You are helpful.'));
      // The exact wording LFM2.5's template produces.
      expect(result[0].content, contains('List of tools: ['));
      expect(result[0].content, contains('"name":"calculator"'));
      expect(result[1].role, 'user');
    });

    test('prepends a system message when none exists', () {
      final result = injectToolDefinitions(
        [IsolateMessage(role: 'user', content: 'hi')],
        schemas,
        format: ToolCallFormat.lfm2,
      );

      expect(result, hasLength(2));
      expect(result[0].role, 'system');
      expect(result[0].content, startsWith('List of tools: ['));
      expect(result[1].role, 'user');
    });

    test('uses the Hermes tools block for a Hermes template', () {
      final result = injectToolDefinitions(
        [IsolateMessage(role: 'user', content: 'hi')],
        schemas,
        format: ToolCallFormat.hermes,
      );

      expect(result[0].content, contains('<tools>'));
      expect(result[0].content, contains('</tools>'));
      expect(result[0].content, contains('<tool_call>'));
      expect(result[0].content, isNot(contains('List of tools:')));
    });

    test('emits JSON instructions for the json format', () {
      final result = injectToolDefinitions(
        [IsolateMessage(role: 'user', content: 'hi')],
        schemas,
        format: ToolCallFormat.json,
      );

      expect(result[0].content, contains('reply with JSON only'));
      expect(result[0].content, contains('"name":"calculator"'));
    });

    test('emits JSON instructions when no family was identified', () {
      final result = injectToolDefinitions(
        [IsolateMessage(role: 'user', content: 'hi')],
        schemas,
        format: ToolCallFormat.json,
      );

      expect(result[0].content, contains('reply with JSON only'));
    });

    test('does not leave a leading newline on an empty system message', () {
      final result = injectToolDefinitions(
        [
          IsolateMessage(role: 'system', content: ''),
          IsolateMessage(role: 'user', content: 'hi'),
        ],
        schemas,
        format: ToolCallFormat.lfm2,
      );

      expect(result[0].content, startsWith('List of tools: ['));
    });

    test('carries every tool through, not just the first', () {
      final two = [
        json.encode(calculatorSchema),
        json.encode({'name': 'get_time', 'description': 'Current time'}),
      ];

      final result = injectToolDefinitions(
        [IsolateMessage(role: 'user', content: 'hi')],
        two,
        format: ToolCallFormat.lfm2,
      );

      expect(result[0].content, contains('calculator'));
      expect(result[0].content, contains('get_time'));
    });
  });
}
