import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/vllm_stream_converter.dart';
import 'package:test/test.dart';

void main() {
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
        final delta = parsed.single.message!.toolCallDeltas!.single;
        expect(delta.name, 'get_weather');
        expect(delta.argumentsDelta, isNull, reason: 'function was $function');
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
