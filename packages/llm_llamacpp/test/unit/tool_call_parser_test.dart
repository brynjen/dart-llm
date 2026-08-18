library;

import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/tool_call_parser.dart';
import 'package:llm_llamacpp/src/tool_calls/tool_call_syntax.dart';
import 'package:test/test.dart';

/// Decodes a call's arguments so assertions do not depend on key order or spacing.
Map<String, dynamic> args(LLMToolCall call) =>
    json.decode(call.arguments) as Map<String, dynamic>;

void main() {
  group('ToolCallParser JSON formats', () {
    test('assigns non-empty ids for JSON format', () {
      const content = '{"name": "calculator", "arguments": {"a": 2, "b": 2}}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.id, isNotNull);
      expect(calls.first.id, isNotEmpty);
      expect(calls.first.name, 'calculator');
      expect(args(calls.first), {'a': 2, 'b': 2});
    });

    test('assigns non-empty ids for function-style format', () {
      const content = 'calculator({"a": 2, "b": 2})';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.id, isNotEmpty);
      expect(calls.first.name, 'calculator');
      expect(args(calls.first), {'a': 2, 'b': 2});
    });

    test('accepts `parameters` as an alias for `arguments`', () {
      const content = '{"name": "get_time", "parameters": {"tz": "UTC"}}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(args(calls.first), {'tz': 'UTC'});
    });

    test('unwraps the OpenAI function envelope', () {
      const content =
          '{"type": "function", "function": {"name": "ping", '
          '"arguments": {"n": 1}}}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'ping');
      expect(args(calls.first), {'n': 1});
    });

    test('treats a flat object as name plus arguments', () {
      const content = '{"name": "calculator", "operation": "add", "a": 1}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(args(calls.first), {'operation': 'add', 'a': 1});
    });

    test('braces inside string values do not break the scan', () {
      const content = '{"name": "say", "arguments": {"text": "a } b { c"}}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(args(calls.first), {'text': 'a } b { c'});
    });
  });

  group('ToolCallParser LFM2 (Pythonic)', () {
    test('parses the canonical LFM2 tool call', () {
      const content =
          "<|tool_call_start|>[get_candidate_status(candidate_id='12345')]"
          '<|tool_call_end|>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_candidate_status');
      expect(args(calls.first), {'candidate_id': '12345'});
    });

    test('converts Python literals to JSON equivalents', () {
      const content =
          '<|tool_call_start|>[f(t=True, f=False, n=None, i=-42, d=3.5)]'
          '<|tool_call_end|>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(args(calls.first), {
        't': true,
        'f': false,
        'n': null,
        'i': -42,
        'd': 3.5,
      });
    });

    test('parses nested collections', () {
      const content =
          "<|tool_call_start|>[f(l=[1, 2], m={'k': 'v', 'n': [true]})]"
          '<|tool_call_end|>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(args(calls.first), {
        'l': [1, 2],
        'm': {
          'k': 'v',
          'n': [true],
        },
      });
    });

    test('unescapes single-quoted strings the way the template escapes them', () {
      // LFM2.5's format_arg_value escapes \, ', \n and \r.
      const content =
          r"<|tool_call_start|>[note(text='it\'s a\nnew line')]<|tool_call_end|>";

      final calls = ToolCallParser.parseToolCalls(content);

      expect(args(calls.first), {'text': "it's a\nnew line"});
    });

    test('parses multiple calls in one bracket list', () {
      const content = "<|tool_call_start|>[a(x=1), b(y='z')]<|tool_call_end|>";

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls.map((c) => c.name), ['a', 'b']);
    });

    test('parses a call with no arguments', () {
      const content = '<|tool_call_start|>[ping()]<|tool_call_end|>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(args(calls.first), isEmpty);
    });

    test('strips surrounding prose and keeps only the call', () {
      const content =
          'Let me check that. '
          "<|tool_call_start|>[get_time(tz='UTC')]<|tool_call_end|>"
          ' One moment.';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_time');
    });

    test('salvages the malformed call observed from a real LFM2.5 run', () {
      // Missing the opening paren and carrying a stray closing one. Recovered
      // only because it arrived inside explicit delimiters.
      const content =
          '<|tool_call_start|>[calculator arguments="multiply", a=347, b=89)]'
          '<|tool_call_end|>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'calculator');
      expect(args(calls.first), {'arguments': 'multiply', 'a': 347, 'b': 89});
    });

    test('parses the complete verbatim device output, prose and all', () {
      // Exactly what LFM2.5-1.2B-Instruct-Q4_K_M produced on an Android arm64
      // emulator, including the narration it appended after the closing
      // delimiter. Reported as: the call was rendered verbatim in the chat
      // bubble instead of being executed.
      const content =
          '<|tool_call_start|>[calculator arguments="multiply", a=347, b=89)]'
          '<|tool_call_end|>I am performing the multiplication of 347 by 89 '
          'using the calculator tool.';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'calculator');
      expect(args(calls.first), {'arguments': 'multiply', 'a': 347, 'b': 89});
    });

    test('an unterminated call yields nothing rather than a partial call', () {
      const content = '<|tool_call_start|>[calculator(operation=';

      expect(ToolCallParser.parseToolCalls(content), isEmpty);
    });
  });

  group('ToolCallParser other families', () {
    test('parses Hermes/Qwen tool_call tags', () {
      const content =
          '<tool_call>\n{"name": "calculator", "arguments": {"a": 1}}\n'
          '</tool_call>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'calculator');
    });

    test('parses repeated Hermes tags as separate calls', () {
      const content =
          '<tool_call>{"name": "a", "arguments": {}}</tool_call>'
          '<tool_call>{"name": "b", "arguments": {}}</tool_call>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls.map((c) => c.name), ['a', 'b']);
    });

    test('parses Mistral TOOL_CALLS arrays', () {
      const content =
          '[TOOL_CALLS][{"name": "calculator", "arguments": {"a": 1}}]';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'calculator');
    });

    test('parses Llama 3.x python_tag calls', () {
      const content = "<|python_tag|>get_time(tz='UTC')";

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_time');
      expect(args(calls.first), {'tz': 'UTC'});
    });

    test('parses a bare Pythonic call list', () {
      const content = "[get_time(tz='UTC')]";

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_time');
    });
  });

  group('ToolCallParser rejects non-calls', () {
    test('plain prose yields nothing', () {
      expect(
        ToolCallParser.parseToolCalls('The capital of France is Paris.'),
        isEmpty,
      );
    });

    test('a bracketed list of values is not a call list', () {
      expect(ToolCallParser.parseToolCalls('Scores: [1, 2, 3]'), isEmpty);
    });

    test('a markdown link is not a call list', () {
      expect(
        ToolCallParser.parseToolCalls('See [the docs](https://x.dev) first.'),
        isEmpty,
      );
    });

    test('JSON without a name is not a call', () {
      expect(ToolCallParser.parseToolCalls('{"result": 42}'), isEmpty);
    });
  });

  group('ToolCallParser deduplication', () {
    test('a Hermes-tagged call is counted once, not once per pass', () {
      // Regression: the previous parser ran a JSON pass, an XML pass and a
      // function-style pass over the whole output, so this produced two calls.
      const content =
          '<tool_call>{"name": "calculator", "arguments": {"a": 1}}</tool_call>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, hasLength(1));
      expect(calls.first.id, 'call_0');
    });

    test('identical repeated calls collapse and ids stay sequential', () {
      const content =
          '<tool_call>{"name": "a", "arguments": {"x": 1}}</tool_call>'
          '<tool_call>{"name": "a", "arguments": {"x": 1}}</tool_call>'
          '<tool_call>{"name": "b", "arguments": {}}</tool_call>';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls.map((c) => c.name), ['a', 'b']);
      expect(calls.map((c) => c.id), ['call_0', 'call_1']);
    });
  });

  group('ToolCallFormat detection', () {
    test('detects families from their chat-template delimiters', () {
      expect(
        ToolCallFormat.detectFromChatTemplate('{{ "<|tool_call_start|>[" }}'),
        ToolCallFormat.lfm2,
      );
      expect(
        ToolCallFormat.detectFromChatTemplate('{{ "<tool_call>" }}'),
        ToolCallFormat.hermes,
      );
      expect(
        ToolCallFormat.detectFromChatTemplate('{% if tools %}<tools>'),
        ToolCallFormat.hermes,
      );
      expect(
        ToolCallFormat.detectFromChatTemplate('{{ "[TOOL_CALLS]" }}'),
        ToolCallFormat.mistral,
      );
    });

    test('returns null for a template with no tool support', () {
      expect(
        ToolCallFormat.detectFromChatTemplate(
          '{{ bos_token }}{% for m in messages %}{{ m.content }}{% endfor %}',
        ),
        isNull,
      );
      expect(ToolCallFormat.detectFromChatTemplate(null), isNull);
      expect(ToolCallFormat.detectFromChatTemplate(''), isNull);
    });

    test('content detection beats prose', () {
      expect(
        ToolCallFormat.detectFromContent('<|tool_call_start|>[f()]'),
        ToolCallFormat.lfm2,
      );
      expect(ToolCallFormat.detectFromContent('just text'), isNull);
    });
  });
}
