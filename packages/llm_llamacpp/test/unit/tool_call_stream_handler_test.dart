library;

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/tool_call_stream_handler.dart';
import 'package:test/test.dart';

/// Feeds [tokens] through a handler and returns what the user would have seen
/// plus the calls that were collected.
({String visible, List<String> calls}) drive(List<String> tokens) {
  final handler = ToolCallStreamHandler(
    logger: DefaultLLMLogger('test'),
    // Only the emptiness of this list matters to the handler.
    tools: const [Object()],
  );

  final visible = StringBuffer();
  for (final token in tokens) {
    final result = handler.processToken(token);
    if (result.shouldYield && result.content != null) {
      visible.write(result.content);
    }
  }
  final tail = handler.finalize(hasTools: true);
  if (tail != null) visible.write(tail);

  return (
    visible: visible.toString(),
    calls: [
      for (final c in handler.collectedToolCalls) '${c.name}:${c.arguments}',
    ],
  );
}

void main() {
  group('ToolCallStreamHandler suppresses tool calls', () {
    test('LFM2 call arriving as one delimiter token is never shown', () {
      final r = drive([
        '<|tool_call_start|>',
        '[',
        'calc',
        'ulator',
        '(op',
        "eration='multiply'",
        ', a=347',
        ', b=89)',
        ']',
        '<|tool_call_end|>',
      ]);

      expect(r.visible, isEmpty);
      expect(r.calls, hasLength(1));
      expect(r.calls.first, contains('calculator'));
      expect(r.calls.first, contains('347'));
    });

    test('replays the exact reported device token sequence', () {
      // On the device the delimiters arrived as single tokens (ids 10 and 11)
      // and the model appended narration after the closing one. The call must be
      // captured and suppressed while the narration still reaches the user.
      final r = drive([
        '<|tool_call_start|>',
        '[calculator arguments="multiply", a=347, b=89)]',
        '<|tool_call_end|>',
        'I am performing the multiplication of 347 by 89 ',
        'using the calculator tool.',
      ]);

      expect(r.calls, hasLength(1));
      expect(r.calls.first, contains('calculator'));
      expect(
        r.visible,
        'I am performing the multiplication of 347 by 89 using the calculator '
        'tool.',
      );
      expect(r.visible, isNot(contains('tool_call_start')));
    });

    test('a delimiter split across tokens never leaks a fragment', () {
      // Regression: the handler used to trigger only on '{', so the '<' and the
      // rest of an LFM2 delimiter were emitted to the user as text.
      final r = drive([
        '<',
        '|tool',
        '_call_',
        'start|>',
        "[calculator(operation='add', a=1, b=2)]",
        '<|tool_call_end|>',
      ]);

      expect(r.visible, isEmpty);
      expect(r.calls, hasLength(1));
    });

    test('Hermes tags are suppressed', () {
      final r = drive([
        '<tool_call>',
        '{"name": "calculator",',
        ' "arguments": {"a": 1}}',
        '</tool_call>',
      ]);

      expect(r.visible, isEmpty);
      expect(r.calls, hasLength(1));
    });

    test('Mistral calls resolve at end of stream', () {
      // [TOOL_CALLS] has no closing delimiter, so the call can only be settled
      // once the stream ends.
      final r = drive([
        '[TOOL_CALLS]',
        '[{"name": "calculator", "arguments": {"a": 1}}]',
      ]);

      expect(r.visible, isEmpty);
      expect(r.calls, hasLength(1));
    });

    test('bare JSON is suppressed', () {
      final r = drive(['{"name": "calculator", ', '"arguments": {"a": 1}}']);

      expect(r.visible, isEmpty);
      expect(r.calls, hasLength(1));
    });
  });

  group('ToolCallStreamHandler preserves prose', () {
    test('text before a call still reaches the user', () {
      final r = drive([
        'Let me ',
        'compute that. ',
        '<|tool_call_start|>',
        "[calculator(operation='add', a=1, b=2)]",
        '<|tool_call_end|>',
      ]);

      expect(r.visible, 'Let me compute that. ');
      expect(r.calls, hasLength(1));
    });

    test('a lone angle bracket is released, not swallowed', () {
      final r = drive(['If a ', '< b ', 'then done.']);

      expect(r.visible, 'If a < b then done.');
      expect(r.calls, isEmpty);
    });

    test('bracketed prose survives intact', () {
      final r = drive(['See ', '[the docs]', ' for more.']);

      expect(r.visible, 'See [the docs] for more.');
      expect(r.calls, isEmpty);
    });

    test('a plain answer passes through unchanged', () {
      final r = drive(['The capital ', 'of France ', 'is Paris.']);

      expect(r.visible, 'The capital of France is Paris.');
      expect(r.calls, isEmpty);
    });

    test('JSON that is not a tool call is shown to the user', () {
      final r = drive(['Here it is: ', '{"result": 42}']);

      expect(r.visible, 'Here it is: {"result": 42}');
      expect(r.calls, isEmpty);
    });
  });

  group('ToolCallStreamHandler accumulates', () {
    test('accumulatedContent keeps the raw text including call markup', () {
      final handler = ToolCallStreamHandler(
        logger: DefaultLLMLogger('test'),
        tools: const [Object()],
      );
      for (final t in [
        'hi ',
        '<|tool_call_start|>',
        '[f()]',
        '<|tool_call_end|>',
      ]) {
        handler.processToken(t);
      }
      handler.finalize(hasTools: true);

      // The repository replays this as the assistant turn when feeding tool
      // results back, so the markers have to survive here.
      expect(handler.accumulatedContent, contains('<|tool_call_start|>'));
      expect(handler.accumulatedContent, startsWith('hi '));
    });

    test('finalize without tools does not invent calls', () {
      final handler = ToolCallStreamHandler(
        logger: DefaultLLMLogger('test'),
        tools: const [],
      );
      handler.processToken('{"name": "calculator", "arguments": {}}');
      handler.finalize(hasTools: false);

      expect(handler.collectedToolCalls, isEmpty);
    });
  });
}
