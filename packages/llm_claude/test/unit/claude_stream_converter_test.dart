import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_claude/src/claude_stream_converter.dart';
import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

http.StreamedResponse _makeResponse(String sseBody) {
  final bytes = utf8.encode(sseBody);
  return http.StreamedResponse(Stream.value(bytes), 200);
}

String _sse(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${json.encode(data)}\n\n';

void main() {
  group('ClaudeStreamConverter', () {
    test('reports the tool name before the call completes', () async {
      // Claude names the tool in content_block_start, before a single
      // argument byte exists, so the name is knowable earlier here than on
      // any OpenAI-shaped backend.
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('content_block_start', {
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_01T1x1',
              'name': 'get_weather',
              'input': <String, dynamic>{},
            },
          }) +
          // The first delta of a block is routinely empty.
          _sse('content_block_delta', {
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': ''},
          }) +
          _sse('content_block_delta', {
            'index': 1,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"location":',
            },
          }) +
          _sse('content_block_delta', {
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': ' "Oslo"}'},
          }) +
          _sse('content_block_stop', {'index': 1}) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 5},
          }) +
          _sse('message_stop', <String, dynamic>{});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      final deltas = chunks
          .expand(
            (c) => c.message?.toolCallDeltas ?? const <LLMToolCallDelta>[],
          )
          .toList();

      // Block start plus two non-empty fragments — the empty one is dropped,
      // since it would be a second phantom "started" signal.
      expect(deltas, hasLength(3));
      expect(deltas.first.name, 'get_weather');
      expect(deltas.first.id, 'toolu_01T1x1');
      expect(deltas.first.index, 1);
      expect(deltas.first.argumentsDelta, isNull);

      // The name arrives before anything reports a completed call.
      final nameAt = chunks.indexWhere(
        (c) => c.message?.toolCallDeltas?.any((d) => d.name != null) ?? false,
      );
      final completedAt = chunks.indexWhere(
        (c) => c.message?.toolCalls?.isNotEmpty ?? false,
      );
      expect(nameAt, lessThan(completedAt));

      // Fragments rebuild exactly what the completed call reports.
      final rebuilt = deltas.map((d) => d.argumentsDelta ?? '').join();
      final completed = chunks[completedAt].message!.toolCalls!.single;
      expect(completed.name, 'get_weather');
      expect(json.decode(rebuilt), json.decode(completed.arguments));
    });

    test('a mid-stream overload is reported as a retryable 529', () async {
      // Anthropic reports in-stream failures by `type`, not a numeric code,
      // and retry classification works off the status code. Without the
      // mapping a mid-stream overload was never recognized as retryable.
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('error', {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          });

      await expectLater(
        ClaudeStreamConverter.toLLMStream(_makeResponse(body)).toList(),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.statusCode, 'statusCode', 529)
              .having((e) => e.message, 'message', contains('Overloaded')),
        ),
      );

      // And 529 has to actually be in the retryable set, or the mapping is
      // decorative.
      expect(
        const RetryConfig().shouldRetryForStatusCode(529),
        isTrue,
        reason: "529 is Anthropic's transient overload signal",
      );
    });

    test('truncated tool input surfaces instead of becoming {}', () async {
      // A turn cut short by max_tokens — or the fine-grained tool streaming
      // beta, which emits unvalidated partial JSON — leaves the accumulated
      // input unparseable. Swallowing that into `{}` ran the tool with *no
      // arguments*, which is worse than failing: the model asked for
      // something specific and the tool did something else.
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('content_block_start', {
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'run_command',
              'input': <String, dynamic>{},
            },
          }) +
          _sse('content_block_delta', {
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"command": "rm -r',
            },
          }) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 5},
          }) +
          _sse('message_stop', <String, dynamic>{});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      final call = chunks
          .firstWhere((c) => c.message?.toolCalls?.isNotEmpty ?? false)
          .message!
          .toolCalls!
          .single;

      // The truncation is visible rather than erased.
      expect(call.arguments, '{"command": "rm -r');
      expect(call.arguments, isNot('{}'));
      expect(() => call.argumentsJson, throwsFormatException);
    });

    test('a complete tool call keeps the wire text verbatim', () async {
      // Byte-identical to the concatenated deltas, as on every other backend.
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('content_block_start', {
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'calculator',
              'input': <String, dynamic>{},
            },
          }) +
          _sse('content_block_delta', {
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"expression": "15 * 7"}',
            },
          }) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 5},
          }) +
          _sse('message_stop', <String, dynamic>{});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      final rebuilt = chunks
          .expand(
            (c) => c.message?.toolCallDeltas ?? const <LLMToolCallDelta>[],
          )
          .map((d) => d.argumentsDelta ?? '')
          .join();
      final call = chunks
          .firstWhere((c) => c.message?.toolCalls?.isNotEmpty ?? false)
          .message!
          .toolCalls!
          .single;

      expect(call.arguments, '{"expression": "15 * 7"}');
      expect(rebuilt, call.arguments);
      expect(call.argumentsJson['expression'], '15 * 7');
    });

    test('emits text content chunks from text_delta events', () async {
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('content_block_start', {
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          }) +
          _sse('content_block_delta', {
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hello'},
          }) +
          _sse('content_block_delta', {
            'index': 0,
            'delta': {'type': 'text_delta', 'text': ' world'},
          }) +
          _sse('content_block_stop', {'index': 0}) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 5},
          }) +
          _sse('message_stop', {});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'claude-opus-4-6',
      ).toList();

      final contentChunks = chunks
          .where((c) => c.message?.content?.isNotEmpty == true)
          .toList();
      expect(contentChunks.length, 2);
      expect(contentChunks[0].message?.content, 'Hello');
      expect(contentChunks[1].message?.content, ' world');
      expect(contentChunks[0].done, false);
    });

    test('emits done chunk on message_stop with token counts', () async {
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 10},
            },
          }) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 5},
          }) +
          _sse('message_stop', {});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      final done = chunks.last;
      expect(done.done, true);
      expect(done.promptEvalCount, 10);
      expect(done.evalCount, 5);
    });

    test(
      'accumulates tool call blocks and emits on tool_use stop_reason',
      () async {
        final body =
            _sse('message_start', {
              'message': {
                'model': 'claude-opus-4-6',
                'usage': {'input_tokens': 20},
              },
            }) +
            _sse('content_block_start', {
              'index': 0,
              'content_block': {
                'type': 'tool_use',
                'id': 'toolu_01',
                'name': 'calculator',
              },
            }) +
            _sse('content_block_delta', {
              'index': 0,
              'delta': {'type': 'input_json_delta', 'partial_json': '{"expr'},
            }) +
            _sse('content_block_delta', {
              'index': 0,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': 'ession": "2+2"}',
              },
            }) +
            _sse('content_block_stop', {'index': 0}) +
            _sse('message_delta', {
              'delta': {'stop_reason': 'tool_use'},
              'usage': {'output_tokens': 15},
            }) +
            _sse('message_stop', {});

        final chunks = await ClaudeStreamConverter.toLLMStream(
          _makeResponse(body),
        ).toList();

        final toolChunk = chunks.firstWhere(
          (c) => c.message?.toolCalls?.isNotEmpty == true,
          orElse: () => throw StateError('no tool chunk'),
        );
        expect(toolChunk.message?.toolCalls?.first.name, 'calculator');
        expect(toolChunk.message?.toolCalls?.first.id, 'toolu_01');
        final args =
            json.decode(toolChunk.message!.toolCalls!.first.arguments) as Map;
        expect(args['expression'], '2+2');
      },
    );

    test('emits thinking chunks from thinking_delta events', () async {
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-opus-4-6',
              'usage': {'input_tokens': 5},
            },
          }) +
          _sse('content_block_start', {
            'index': 0,
            'content_block': {'type': 'thinking', 'thinking': ''},
          }) +
          _sse('content_block_delta', {
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': 'Let me think...'},
          }) +
          _sse('content_block_stop', {'index': 0}) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 3},
          }) +
          _sse('message_stop', {});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      final thinkingChunks = chunks
          .where((c) => c.message?.thinking?.isNotEmpty == true)
          .toList();
      expect(thinkingChunks.length, 1);
      expect(thinkingChunks.first.message?.thinking, 'Let me think...');
    });

    test('resolves model from message_start event', () async {
      final body =
          _sse('message_start', {
            'message': {
              'model': 'claude-sonnet-4-6',
              'usage': {'input_tokens': 1},
            },
          }) +
          _sse('message_delta', {
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 1},
          }) +
          _sse('message_stop', {});

      final chunks = await ClaudeStreamConverter.toLLMStream(
        _makeResponse(body),
      ).toList();

      expect(chunks.last.model, 'claude-sonnet-4-6');
    });
  });
}
