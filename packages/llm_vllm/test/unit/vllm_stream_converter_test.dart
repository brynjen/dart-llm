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

      expect(parsed, hasLength(1));
      final toolCall = parsed.single.message?.toolCalls?.single;
      expect(toolCall?.id, 'call_1');
      expect(toolCall?.name, 'calculator');
      expect(toolCall?.arguments, '{"expression":"2+2"}');
      expect(parsed.single.finishReason, LLMFinishReason.toolCalls);
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
