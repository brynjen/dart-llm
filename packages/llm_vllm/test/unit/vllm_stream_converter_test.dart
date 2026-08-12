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

    test('throws after malformed-event retry budget is exceeded', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: not-json-1\n\n'
            'data: not-json-2\n\n'
            'data: not-json-3\n\n'
            'data: not-json-4\n\n',
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
            contains('Failed to parse vLLM SSE stream'),
          ),
        ),
      );
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
