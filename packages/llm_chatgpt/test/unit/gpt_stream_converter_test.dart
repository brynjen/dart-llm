library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/src/gpt_stream_converter.dart';
import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

String _sse(List<Map<String, dynamic>> events) =>
    '${events.map((e) => 'data: ${json.encode(e)}').join('\n\n')}\n\ndata: [DONE]\n\n';

Map<String, dynamic> _chunk(Map<String, dynamic> delta, {String? finish}) => {
  'id': 'chatcmpl-test',
  'object': 'chat.completion.chunk',
  'created': 1700000000,
  'model': 'gpt-test',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Future<List<LLMChunk>> _run(List<Map<String, dynamic>> events) =>
    GPTStreamConverter.toLLMStream(
      http.StreamedResponse(Stream.value(utf8.encode(_sse(events))), 200),
    ).toList();

void main() {
  group('GPTStreamConverter tool call streaming', () {
    test('reports the tool name before the call completes', () async {
      final parsed = await _run([
        // OpenAI's priming event.
        _chunk({'role': 'assistant', 'content': ''}),
        // First fragment: id + name, arguments is "".
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'get_weather', 'arguments': ''},
            },
          ],
        }),
        // Continuations: id and name are explicitly null.
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': null,
              'type': null,
              'function': {'name': null, 'arguments': '{"city":'},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': null,
              'type': null,
              'function': {'name': null, 'arguments': '"Oslo"}'},
            },
          ],
        }),
        _chunk(<String, dynamic>{}, finish: 'tool_calls'),
      ]);

      // Priming event suppressed; three fragments then the completed call.
      expect(parsed, hasLength(4));

      final first = parsed.first.message!.toolCallDeltas!.single;
      expect(first.name, 'get_weather');
      expect(first.id, 'call_1');
      // "" is not a fragment.
      expect(first.argumentsDelta, isNull);
      expect(parsed.first.message?.toolCalls, isNull);

      final rebuilt = parsed
          .take(3)
          .expand((c) => c.message?.toolCallDeltas ?? const [])
          .map((d) => d.argumentsDelta ?? '')
          .join();

      final completed = parsed.last.message!.toolCalls!.single;
      expect(completed.name, 'get_weather');
      expect(completed.arguments, '{"city":"Oslo"}');
      expect(rebuilt, completed.arguments);
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
    });

    test('correlates fragments by index, not by the last id seen', () async {
      // Continuation fragments carry `id: null` by design. Keying off the
      // most recently seen id attributed them to whichever call started
      // last, so an interleaved second call corrupted the first one's
      // arguments.
      final parsed = await _run([
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_a',
              'type': 'function',
              'function': {'name': 'alpha', 'arguments': ''},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 1,
              'id': 'call_b',
              'type': 'function',
              'function': {'name': 'beta', 'arguments': ''},
            },
          ],
        }),
        // Belongs to index 0, but arrives after index 1 has started.
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"a":1}'},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 1,
              'function': {'arguments': '{"b":2}'},
            },
          ],
        }),
        _chunk(<String, dynamic>{}, finish: 'tool_calls'),
      ]);

      final deltas = parsed
          .expand((c) => c.message?.toolCallDeltas ?? const [])
          .toList();
      final forIndexZero = deltas
          .where((d) => d.index == 0)
          .map((d) => d.argumentsDelta ?? '')
          .join();
      final forIndexOne = deltas
          .where((d) => d.index == 1)
          .map((d) => d.argumentsDelta ?? '')
          .join();

      expect(forIndexZero, '{"a":1}');
      expect(forIndexOne, '{"b":2}');
      expect(deltas.firstWhere((d) => d.index == 1).name, 'beta');
    });

    test('keeps parallel calls apart when a server reuses index 0', () async {
      // Some OpenAI-compatible servers and proxies emit every parallel call
      // with index 0. Correlating on index alone merges them into one
      // malformed call.
      final parsed = await _run([
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_a',
              'type': 'function',
              'function': {'name': 'alpha', 'arguments': ''},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"a":1}'},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_b',
              'type': 'function',
              'function': {'name': 'beta', 'arguments': ''},
            },
          ],
        }),
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"b":2}'},
            },
          ],
        }),
        _chunk(<String, dynamic>{}, finish: 'tool_calls'),
      ]);

      final completed = parsed.last.message!.toolCalls!;
      expect(completed, hasLength(2));
      expect(completed[0].name, 'alpha');
      expect(completed[0].arguments, '{"a":1}');
      expect(completed[1].name, 'beta');
      expect(completed[1].arguments, '{"b":2}');
    });

    test('throws on an in-stream error event', () async {
      // Parsed as an ordinary frame this has no choices and no usage, so it
      // used to be skipped and the stream ended as a success carrying a
      // truncated answer.
      await expectLater(
        GPTStreamConverter.toLLMStream(
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: ${json.encode(_chunk({'content': 'partial'}))}\n\n'
                'data: ${json.encode({
                  'error': {'message': 'upstream is overloaded', 'code': 503},
                })}\n\n',
              ),
            ),
            200,
          ),
        ).toList(),
        throwsA(
          isA<LLMApiException>()
              // The status code has to survive: retry classification works off
              // it, so without it a mid-stream 503 is never retried.
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', contains('overloaded')),
        ),
      );
    });

    test('a completion without tools is unchanged', () async {
      final parsed = await _run([
        _chunk({'role': 'assistant', 'content': ''}),
        _chunk({'content': 'Hello'}),
        _chunk({'content': ' there'}),
        _chunk(<String, dynamic>{}, finish: 'stop'),
      ]);

      // Two content chunks plus the terminal chunk; the priming event is the
      // only thing that changed.
      expect(parsed, hasLength(3));
      expect(parsed.map((c) => c.message?.content).toList(), [
        'Hello',
        ' there',
        null,
      ]);
      expect(parsed.every((c) => c.message?.toolCallDeltas == null), isTrue);
      expect(parsed.last.finishReason, LLMFinishReason.stop);
    });
  });
}
