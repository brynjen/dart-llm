import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/vllm_stream_converter.dart';
import 'package:test/test.dart';

void main() {
  _turnEndEmissionTests();

  group('VLLMStreamConverter', () {
    test('parses SSE split across transport chunk boundaries', () async {
      final payload = _sse([
        {
          'id': 'chatcmpl-test',
          'created': 1700000000,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Hel'},
              'finish_reason': null,
            },
          ],
        },
        {
          'id': 'chatcmpl-test',
          'created': 1700000000,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'lo'},
              'finish_reason': 'stop',
            },
          ],
        },
      ]);
      final bytes = utf8.encode(payload);
      final splitIndex = bytes.length ~/ 2;
      final response = http.StreamedResponse(
        Stream.fromIterable([
          bytes.sublist(0, splitIndex),
          bytes.sublist(splitIndex),
        ]),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      expect(parsed.length, 2);
      expect(parsed.first.message?.content, 'Hel');
      expect(parsed.last.message?.content, 'lo');
      expect(parsed.last.done, isTrue);
    });

    test('throws immediately when stream frame contains error', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: ${json.encode({
              'error': {'message': 'model does not support chat'},
            })}\n\n',
          ),
        ),
        200,
      );

      expect(
        () async => VLLMStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('vLLM stream error'),
          ),
        ),
      );
    });

    test('stream error carries statusCode so retry can classify it', () async {
      // Without a statusCode, ErrorHandlers.isRetryableError can never
      // recognize a mid-stream 429/503 as retryable.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: ${json.encode({
              'error': {'message': 'overloaded', 'code': 503},
            })}\n\n',
          ),
        ),
        200,
      );

      expect(
        () async => VLLMStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having(
                (e) => e.responseBody,
                'responseBody',
                contains('overloaded'),
              ),
        ),
      );
    });

    test('stream error with string code still parses', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: ${json.encode({
              'error': {'message': 'bad', 'code': '400'},
            })}\n\n',
          ),
        ),
        200,
      );

      expect(
        () async => VLLMStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('throws on the third malformed event, matching the message', () async {
      // The guard and the message used to disagree: it threw on the 4th
      // event while claiming "after 3 malformed events".
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: not-json-1\n\n'
            'data: not-json-2\n\n'
            'data: not-json-3\n\n',
          ),
        ),
        200,
      );

      expect(
        () async => VLLMStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('after 3 malformed events'),
          ),
        ),
      );
    });

    test('two malformed events followed by valid data recover', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: not-json-1\n\n'
            'data: not-json-2\n\n'
            '${_sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': 'ok'},
                    'finish_reason': 'stop',
                  },
                ],
              },
            ])}',
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.single.message?.content, 'ok');
    });

    test('a complete call is kept when the finish reason is stop', () async {
      // vLLM reports `stop` even when the choice carried tool calls. The
      // converter used to match only `tool_calls`, fall through, and yield a
      // bare chunk — dropping a complete, executable call. Downstream that is
      // a round with no content and no calls, indistinguishable from the model
      // idling, and a whole round of decode wasted.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_1',
                          'index': 0,
                          'type': 'function',
                          'function': {
                            'name': 'calculator',
                            'arguments': '{"expression":"2+2"}',
                          },
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      final calls = parsed.last.message?.toolCalls;
      expect(calls, isNotNull, reason: 'the call must survive a stop finish');
      expect(calls!.single.name, 'calculator');
      expect(calls.single.arguments, '{"expression":"2+2"}');
    });

    test('a call cut off by length stays a truncation', () async {
      // The opposite case, and it must not be normalised: arguments cut
      // mid-JSON are not executable, so the caller sees the truncation and the
      // call as invalid rather than receiving a malformed executable call.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_1',
                          'index': 0,
                          'type': 'function',
                          'function': {
                            'name': 'calculator',
                            'arguments': '{"expression"',
                          },
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'length'},
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.message?.toolCalls, isNull);
      expect(parsed.last.message?.invalidToolCalls?.single.name, 'calculator');
      expect(parsed.last.finishReason, LLMFinishReason.length);
    });

    test('accumulates streamed tool call arguments', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_1',
                          'index': 0,
                          'type': 'function',
                          'function': {
                            'name': 'calculator',
                            'arguments': '{"expression"',
                          },
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'function': {'arguments': ':"2+2"}'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'},
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      // Two fragment events, then the completed call. The fragments used to
      // yield nothing at all, which is what made a streamed call invisible
      // until it had finished.
      expect(parsed, hasLength(3));

      // Progress chunks carry fragments only — never an executable call.
      final progress = parsed.take(2).toList();
      expect(progress.every((c) => c.message?.toolCalls == null), isTrue);
      expect(progress.every((c) => c.done ?? false), isFalse);

      final first = progress.first.message!.toolCallDeltas!.single;
      expect(first.index, 0);
      expect(first.id, 'call_1');
      expect(first.name, 'calculator');
      expect(first.argumentsDelta, '{"expression"');

      final second = progress.last.message!.toolCallDeltas!.single;
      expect(second.index, 0);
      expect(second.name, isNull);
      expect(second.argumentsDelta, ':"2+2"}');

      // Fragments concatenate to exactly what the completed call reports.
      final rebuilt = progress
          .expand((c) => c.message!.toolCallDeltas!)
          .map((d) => d.argumentsDelta ?? '')
          .join();

      // The completed call is unchanged from before deltas existed.
      final completed = parsed.last;
      final toolCall = completed.message?.toolCalls?.single;
      expect(toolCall?.id, 'call_1');
      expect(toolCall?.name, 'calculator');
      expect(toolCall?.arguments, '{"expression":"2+2"}');
      expect(rebuilt, toolCall?.arguments);
      expect(completed.finishReason, LLMFinishReason.toolCalls);
      expect(completed.message?.toolCallDeltas, isNull);
    });

    test('completes a tool call fused with the finish reason', () async {
      // Live vLLM ends a tool-call stream in one of two shapes, chosen
      // nondeterministically: a lone `{}` delta carrying finish_reason (the
      // test above), or the final argument fragment fused with it. Captured
      // from a real server, the fused shape was the more common of the two.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_1',
                          'type': 'function',
                          'index': 0,
                          'function': {'name': 'get_weather'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'function': {'arguments': '{"city":"Oslo"}'},
                        },
                      ],
                    },
                    'finish_reason': 'tool_calls',
                  },
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      // The fused chunk completes the call rather than emitting a fragment,
      // so the consumer gets the whole call in that same event.
      expect(parsed, hasLength(2));
      expect(parsed.first.message?.toolCallDeltas?.single.name, 'get_weather');
      expect(parsed.first.message?.toolCalls, isNull);

      final toolCall = parsed.last.message?.toolCalls?.single;
      expect(toolCall?.name, 'get_weather');
      expect(toolCall?.arguments, '{"city":"Oslo"}');
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
    });

    test('a name-only fragment reports no argument text', () async {
      // vLLM omits `arguments` on the name fragment; OpenAI sends "". Both
      // mean the same thing, and neither is a fragment worth reporting.
      for (final function in [
        {'name': 'get_weather'},
        {'name': 'get_weather', 'arguments': ''},
      ]) {
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sse([
                {
                  'id': 'chatcmpl-test',
                  'created': 1700000000,
                  'model': 'test-model',
                  'choices': [
                    {
                      'index': 0,
                      'delta': {
                        'tool_calls': [
                          {
                            'id': 'call_1',
                            'type': 'function',
                            'index': 0,
                            'function': function,
                          },
                        ],
                      },
                      'finish_reason': null,
                    },
                  ],
                },
              ]),
            ),
          ),
          200,
        );

        final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
        final delta = parsed.first.message!.toolCallDeltas!.single;
        expect(delta.name, 'get_weather');
        expect(delta.argumentsDelta, isNull, reason: 'function was $function');
        // The stream then ends abruptly with only the name received: the call
        // is surfaced as invalid, never as executable.
        expect(parsed.last.message?.toolCalls, isNull);
        expect(
          parsed.last.message?.invalidToolCalls?.single.name,
          'get_weather',
        );
      }
    });

    test('keeps parallel calls apart when a server reuses index 0', () async {
      // Some OpenAI-compatible servers and proxies emit every parallel tool
      // call with index 0. Correlating on index alone merges them into one
      // malformed call, so a fragment whose id differs from the call open at
      // that index starts a new call instead.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_a',
                          'type': 'function',
                          'index': 0,
                          'function': {'name': 'alpha'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'function': {'arguments': '{"a":1}'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'id': 'call_b',
                          'type': 'function',
                          'index': 0,
                          'function': {'name': 'beta'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'function': {'arguments': '{"b":2}'},
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'},
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      final completed = parsed.last.message!.toolCalls!;

      expect(completed, hasLength(2));
      expect(completed[0].name, 'alpha');
      expect(completed[0].arguments, '{"a":1}');
      expect(completed[1].name, 'beta');
      expect(completed[1].arguments, '{"b":2}');
    });

    test('suppresses the empty priming delta', () async {
      // vLLM opens every stream with {"role":"assistant","content":""} to
      // announce the role. It carries no output, and yielding it told
      // consumers the model had started producing text before it had.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': ''},
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': 'Hi'},
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      // Content chunk and terminal chunk only — the priming event is gone,
      // and the terminal chunk survives on its finish reason despite also
      // having empty content.
      expect(parsed, hasLength(2));
      expect(parsed.first.message?.content, 'Hi');
      expect(parsed.last.finishReason, LLMFinishReason.stop);
      expect(parsed.last.done, isTrue);
    });

    test('deltas without an explicit role fold into chatResponse', () async {
      // Live vLLM sends `role` only on the first delta of a choice; later
      // content deltas omit it. Those chunks must still report assistant so
      // chatResponse accumulates them — this used to silently drop
      // everything after the first (empty) delta against a real server.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': ''},
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': '{"answer":'},
                    'finish_reason': null,
                  },
                ],
              },
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': ' 4}'},
                    'finish_reason': 'stop',
                  },
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      for (final chunk in parsed) {
        expect(
          chunk.message?.role,
          LLMRole.assistant,
          reason: 'content-bearing deltas must report assistant',
        );
      }
      expect(
        parsed.map((chunk) => chunk.message?.content ?? '').join(),
        '{"answer": 4}',
      );
    });

    test('emits usage-only chunks', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': <dynamic>[],
                'usage': {
                  'prompt_tokens': 1,
                  'completion_tokens': 2,
                  'total_tokens': 3,
                },
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      expect(parsed, hasLength(1));
      expect(parsed.single.message, isNull);
      expect(parsed.single.usage?.totalTokens, 3);
    });

    test(
      'separates qwen think tags from visible content across chunks',
      () async {
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sse([
                {
                  'id': 'chatcmpl-test',
                  'created': 1700000000,
                  'model': 'test-model',
                  'choices': [
                    {
                      'index': 0,
                      'delta': {'role': 'assistant', 'content': '<thi'},
                      'finish_reason': null,
                    },
                  ],
                },
                {
                  'id': 'chatcmpl-test',
                  'created': 1700000000,
                  'model': 'test-model',
                  'choices': [
                    {
                      'index': 0,
                      'delta': {'content': 'nk>I should answer</th'},
                      'finish_reason': null,
                    },
                  ],
                },
                {
                  'id': 'chatcmpl-test',
                  'created': 1700000000,
                  'model': 'test-model',
                  'choices': [
                    {
                      'index': 0,
                      'delta': {'content': 'ink>ok'},
                      'finish_reason': null,
                    },
                  ],
                },
              ]),
            ),
          ),
          200,
        );

        final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

        expect(
          parsed.map((chunk) => chunk.message?.content ?? '').join(),
          'ok',
        );
        expect(
          parsed.map((chunk) => chunk.message?.thinking ?? '').join(),
          'I should answer',
        );
      },
    );

    test('flushes a truncated partial tag at [DONE] as content', () async {
      // "4<thin" ends the stream: the splitter holds "<thin" back as a
      // potential tag start, but nothing can complete it anymore — dropping
      // it would silently truncate the answer.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': '4<thin'},
                    'finish_reason': null,
                  },
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      expect(
        parsed.map((chunk) => chunk.message?.content ?? '').join(),
        '4<thin',
      );
    });

    test('flushes a truncated end tag inside thinking as thinking', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              {
                'id': 'chatcmpl-test',
                'created': 1700000000,
                'model': 'test-model',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'role': 'assistant',
                      'content': '<think>hmm</thi',
                    },
                    'finish_reason': null,
                  },
                ],
              },
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      expect(
        parsed.map((chunk) => chunk.message?.thinking ?? '').join(),
        'hmm</thi',
      );
      expect(parsed.map((chunk) => chunk.message?.content ?? '').join(), '');
    });

    test('flushes carry when the stream closes without [DONE]', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: ${json.encode({
              'id': 'chatcmpl-test',
              'created': 1700000000,
              'model': 'test-model',
              'choices': [
                {
                  'index': 0,
                  'delta': {'role': 'assistant', 'content': 'partial<th'},
                  'finish_reason': null,
                },
              ],
            })}\n\n',
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();

      expect(
        parsed.map((chunk) => chunk.message?.content ?? '').join(),
        'partial<th',
      );
    });
  });
}

String _sse(List<Map<String, dynamic>> frames) {
  final buffer = StringBuffer();
  for (final frame in frames) {
    buffer.writeln('data: ${json.encode(frame)}');
    buffer.writeln();
  }
  buffer.writeln('data: [DONE]');
  buffer.writeln();
  return buffer.toString();
}

/// SSE frames with no `[DONE]` sentinel — the shape a proxy cutoff produces.
String _sseUnterminated(List<Map<String, dynamic>> frames) {
  final buffer = StringBuffer();
  for (final frame in frames) {
    buffer.writeln('data: ${json.encode(frame)}');
    buffer.writeln();
  }
  return buffer.toString();
}

Map<String, dynamic> _callFrame({
  required String arguments,
  String? name,
  String? id,
  String? finish,
  int index = 0,
}) => {
  'id': 'chatcmpl-test',
  'created': 1700000000,
  'model': 'test-model',
  'choices': [
    {
      'index': 0,
      'delta': {
        'tool_calls': [
          {
            'id': ?id,
            'index': index,
            'type': 'function',
            'function': {'name': ?name, 'arguments': arguments},
          },
        ],
      },
      'finish_reason': finish,
    },
  ],
};

Map<String, dynamic> _finishFrame(String finish) => {
  'id': 'chatcmpl-test',
  'created': 1700000000,
  'model': 'test-model',
  'choices': [
    {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': finish},
  ],
};

void _turnEndEmissionTests() {
  group('VLLMStreamConverter turn-end emission', () {
    test('a complete call survives a stream that never terminates', () async {
      // Gating emission on the finish reason lost this outright: a proxy
      // cutoff or server hiccup ends the stream with the call fully
      // accumulated and no `finish_reason` to trigger the flush. The call was
      // complete and executable, and it was dropped in silence.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sseUnterminated([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
              ),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      final calls = parsed.last.message?.toolCalls;
      expect(
        calls,
        isNotNull,
        reason: 'an unterminated stream must not eat it',
      );
      expect(calls!.single.name, 'calculator');
      expect(calls.single.arguments, '{"expression":"2+2"}');
    });

    test(
      'a call cut off mid-arguments is surfaced as invalid at stream end',
      () async {
        // The counterpart to the test above: same absence of a terminal frame,
        // but the arguments never closed. There is no provider signal either
        // way at an abrupt end of stream, so the payload decides — and this one
        // is not executable, but it is not dropped either.
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sseUnterminated([
                _callFrame(
                  id: 'call_1',
                  name: 'calculator',
                  arguments: '{"expression"',
                ),
              ]),
            ),
          ),
          200,
        );

        final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
        for (final chunk in parsed) {
          expect(
            chunk.message?.toolCalls,
            anyOf(isNull, isEmpty),
            reason: 'truncated JSON must never be executable',
          );
        }
        final invalid = parsed.last.message!.invalidToolCalls!.single;
        expect(invalid.name, 'calculator');
        expect(invalid.arguments, '{"expression"');
      },
    );

    test('an unrecognized finish spelling still yields the call', () async {
      // The rule is the presence of complete calls, not a known string. A
      // server spelling its terminal reason differently used to drop them.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
              ),
              _finishFrame('eos_token'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      final calls = parsed.last.message?.toolCalls;
      expect(calls, isNotNull);
      expect(calls!.single.name, 'calculator');
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
    });

    test('a filtered turn does not yield its calls, at the frame or at the '
        'end of the stream', () async {
      // The provider declined the turn. Executing what it produced anyway
      // would bury a safety outcome behind a tool call — and the end-of-stream
      // flush must not resurrect what the terminal frame rejected.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
              ),
              _finishFrame('content_filter'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.contentFilter);
      for (final chunk in parsed) {
        expect(
          chunk.message?.toolCalls,
          anyOf(isNull, isEmpty),
          reason: 'a declined turn must never surface an executable call',
        );
      }
    });

    test('a tool_calls finish with unterminated arguments is restored to '
        'length', () async {
      // vLLM overwrites `length` with `tool_calls` once any tool-call delta
      // went out (vllm-project/vllm#53269). The payload proves the cut.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'write_file',
                arguments: '{"path":"/app/x.py","content":"def f(',
              ),
              _finishFrame('tool_calls'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.length);
      for (final chunk in parsed) {
        expect(chunk.message?.toolCalls, anyOf(isNull, isEmpty));
      }
      final invalid = parsed.last.message!.invalidToolCalls!.single;
      expect(invalid.id, 'call_1');
      expect(invalid.name, 'write_file');
      expect(invalid.arguments, '{"path":"/app/x.py","content":"def f(');
      expect(invalid.error, isNotEmpty);
    });

    test('a tool_calls finish with complete arguments is unchanged', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
              ),
              _finishFrame('tool_calls'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
      expect(parsed.last.message!.toolCalls!.single.name, 'calculator');
      expect(parsed.last.message!.invalidToolCalls, isNull);
    });

    test(
      'a cut second call restores length and keeps the first call',
      () async {
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sse([
                _callFrame(
                  id: 'call_1',
                  name: 'calculator',
                  arguments: '{"expression":"2+2"}',
                ),
                _callFrame(
                  id: 'call_2',
                  name: 'write_file',
                  arguments: '{"path":"/app/x.py","content":"def',
                  index: 1,
                ),
                _finishFrame('tool_calls'),
              ]),
            ),
          ),
          200,
        );

        final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
        expect(parsed.last.finishReason, LLMFinishReason.length);
        expect(parsed.last.message!.toolCalls!.single.id, 'call_1');
        expect(parsed.last.message!.invalidToolCalls!.single.id, 'call_2');
      },
    );

    test('a final fragment fused with a tool_calls finish, still unterminated, '
        'restores length', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'write_file',
                arguments: '{"path":"/app/x.py",',
              ),
              _callFrame(arguments: '"content":"def f(', finish: 'tool_calls'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.length);
      for (final chunk in parsed) {
        expect(chunk.message?.toolCalls, anyOf(isNull, isEmpty));
      }
      expect(
        parsed.last.message!.invalidToolCalls!.single.arguments,
        '{"path":"/app/x.py","content":"def f(',
      );
    });

    test('bad JSON before a complete last call is not a truncation', () async {
      // Only the last call can be cut by the token limit. An earlier call that
      // does not decode is the model writing bad JSON.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":}',
              ),
              _callFrame(
                id: 'call_2',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
                index: 1,
              ),
              _finishFrame('tool_calls'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
      expect(parsed.last.message!.toolCalls!.single.id, 'call_2');
      expect(parsed.last.message!.invalidToolCalls!.single.id, 'call_1');
    });

    test('a length finish surfaces both complete and cut calls', () async {
      // The spec-correct shape, as OpenAI itself sends it: the reason stays a
      // truncation and the calls come back split, not dropped.
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _sse([
              _callFrame(
                id: 'call_1',
                name: 'calculator',
                arguments: '{"expression":"2+2"}',
              ),
              _callFrame(
                id: 'call_2',
                name: 'calculator',
                arguments: '{"expression"',
                index: 1,
              ),
              _finishFrame('length'),
            ]),
          ),
        ),
        200,
      );

      final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.length);
      expect(parsed.last.message!.toolCalls!.single.id, 'call_1');
      expect(parsed.last.message!.invalidToolCalls!.single.id, 'call_2');
    });

    test(
      'a truncated call is surfaced once, and never as executable',
      () async {
        // The `length` frame surfaces the call as invalid and clears the
        // accumulation; the end-of-stream flush must not hand it back again.
        final response = http.StreamedResponse(
          Stream.value(
            utf8.encode(
              _sse([
                _callFrame(
                  id: 'call_1',
                  name: 'calculator',
                  arguments: '{"expression"',
                ),
                _finishFrame('length'),
              ]),
            ),
          ),
          200,
        );

        final parsed = await VLLMStreamConverter.toLLMStream(response).toList();
        expect(parsed.last.finishReason, LLMFinishReason.length);
        for (final chunk in parsed) {
          expect(chunk.message?.toolCalls, anyOf(isNull, isEmpty));
        }
        expect(
          parsed.where((c) => c.message?.invalidToolCalls != null),
          hasLength(1),
        );
      },
    );
  });
}
