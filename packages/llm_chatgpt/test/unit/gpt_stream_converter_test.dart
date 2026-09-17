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
  _turnEndEmissionTests();

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

/// SSE events with no `[DONE]` sentinel — the shape a proxy cutoff produces.
String _sseUnterminated(List<Map<String, dynamic>> events) =>
    '${events.map((e) => 'data: ${json.encode(e)}').join('\n\n')}\n\n';

Map<String, dynamic> _callDelta({
  required String arguments,
  String? name,
  String? id,
  int index = 0,
}) => {
  'tool_calls': [
    {
      'id': ?id,
      'index': index,
      'type': 'function',
      'function': {'name': ?name, 'arguments': arguments},
    },
  ],
};

void _turnEndEmissionTests() {
  group('GPTStreamConverter turn-end emission', () {
    test('a complete call is kept when the finish reason is stop', () async {
      // OpenAI reports `stop` alongside a complete call intermittently, and
      // OpenAI-compatible servers do it deterministically for a named
      // tool_choice. Matching only `tool_calls` dropped a complete, executable
      // call: downstream that is a round with no content and no calls,
      // indistinguishable from the model idling.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _chunk(
                _callDelta(
                  id: 'call_1',
                  name: 'get_weather',
                  arguments: '{"city":"Oslo"}',
                ),
              ),
              _chunk(<String, dynamic>{}, finish: 'stop'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await GPTStreamConverter.toLLMStream(response).toList();
      final calls = parsed.last.message?.toolCalls;
      expect(calls, isNotNull, reason: 'the call must survive a stop finish');
      expect(calls!.single.name, 'get_weather');
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
    });

    test(
      'a tool_calls finish with nothing accumulated still ends the stream',
      () async {
        // This matched neither branch before, so no terminal chunk was emitted
        // at all: chatResponse reported a fabricated `stop` and no usage, and
        // StreamToolExecutor saw no final assistant answer and threw.
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sse([
                _chunk({'content': 'thinking about it'}),
                _chunk(<String, dynamic>{}, finish: 'tool_calls'),
              ]),
            ),
          ),
          200,
        );

        final parsed = await GPTStreamConverter.toLLMStream(response).toList();
        expect(parsed.last.done, isTrue, reason: 'the turn must be closed out');
        expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
      },
    );

    test('a call cut off by length stays a truncation', () async {
      // Arguments cut mid-JSON are not executable; the caller sees the
      // truncation and the call as invalid, never as an executable call.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _chunk(
                _callDelta(
                  id: 'call_1',
                  name: 'get_weather',
                  arguments: '{"city"',
                ),
              ),
              _chunk(<String, dynamic>{}, finish: 'length'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await GPTStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.length);
      for (final chunk in parsed) {
        expect(chunk.message?.toolCalls, anyOf(isNull, isEmpty));
      }
      final invalid = parsed.last.message!.invalidToolCalls!.single;
      expect(invalid.name, 'get_weather');
      expect(invalid.arguments, '{"city"');
    });

    test(
      'a length finish surfaces complete calls next to the cut one',
      () async {
        // OpenAI returns the calls with a `length` finish; so do LangChain and
        // the Vercel AI SDK, split by whether the arguments decode.
        final parsed = await _run([
          _chunk(
            _callDelta(
              id: 'call_1',
              name: 'get_weather',
              arguments: '{"city":"Oslo"}',
            ),
          ),
          _chunk(
            _callDelta(
              id: 'call_2',
              name: 'get_weather',
              arguments: '{"city"',
              index: 1,
            ),
          ),
          _chunk(<String, dynamic>{}, finish: 'length'),
        ]);

        expect(parsed.last.finishReason, LLMFinishReason.length);
        expect(parsed.last.message!.toolCalls!.single.id, 'call_1');
        expect(parsed.last.message!.invalidToolCalls!.single.id, 'call_2');
      },
    );

    test(
      'a tool_calls finish is passed through even with bad arguments',
      () async {
        // OpenAI reports `length` for a truncation itself, so its reason is
        // trusted as sent. Only the vLLM adapter corrects a known violation.
        final parsed = await _run([
          _chunk(
            _callDelta(
              id: 'call_1',
              name: 'get_weather',
              arguments: '{"city":}',
            ),
          ),
          _chunk(<String, dynamic>{}, finish: 'tool_calls'),
        ]);

        expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
        expect(parsed.last.message?.toolCalls, isNull);
        expect(parsed.last.message!.invalidToolCalls!.single.id, 'call_1');
      },
    );

    test('a complete call survives a stream that never terminates', () async {
      // A proxy cutoff ends the stream with the call fully accumulated and no
      // finish reason to trigger the flush.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sseUnterminated([
              _chunk(
                _callDelta(
                  id: 'call_1',
                  name: 'get_weather',
                  arguments: '{"city":"Oslo"}',
                ),
              ),
            ]),
          ),
        ),
        200,
      );

      final parsed = await GPTStreamConverter.toLLMStream(response).toList();
      final calls = parsed.last.message?.toolCalls;
      expect(
        calls,
        isNotNull,
        reason: 'an unterminated stream must not eat it',
      );
      expect(calls!.single.name, 'get_weather');
    });

    test(
      'a call cut off mid-arguments is surfaced as invalid at stream end',
      () async {
        // There is no provider signal either way at an abrupt end of stream, so
        // the payload decides — and this one is not executable.
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sseUnterminated([
                _chunk(
                  _callDelta(
                    id: 'call_1',
                    name: 'get_weather',
                    arguments: '{"city"',
                  ),
                ),
              ]),
            ),
          ),
          200,
        );

        final parsed = await GPTStreamConverter.toLLMStream(response).toList();
        for (final chunk in parsed) {
          expect(chunk.message?.toolCalls, anyOf(isNull, isEmpty));
        }
        expect(
          parsed.last.message!.invalidToolCalls!.single.name,
          'get_weather',
        );
      },
    );
  });
}
