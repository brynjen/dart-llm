import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_claude/src/claude_stream_converter.dart';
import 'package:test/test.dart';

http.StreamedResponse _makeResponse(String sseBody) {
  final bytes = utf8.encode(sseBody);
  return http.StreamedResponse(Stream.value(bytes), 200);
}

String _sse(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${json.encode(data)}\n\n';

void main() {
  group('ClaudeStreamConverter', () {
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
