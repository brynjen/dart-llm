import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_gemini/llm_gemini.dart';
import 'package:llm_gemini/src/gemini_stream_converter.dart';
import 'package:test/test.dart';

http.StreamedResponse _makeResponse(String sseBody) {
  final bytes = utf8.encode(sseBody);
  return http.StreamedResponse(Stream.value(bytes), 200);
}

String _sseLine(Map<String, dynamic> data) => 'data: ${json.encode(data)}\n';

String _created({String model = 'gemini-3.5-flash-lite'}) => _sseLine({
  'event_type': 'interaction.created',
  'interaction': {'id': 'int_1', 'model': model, 'status': 'in_progress'},
});

String _textDelta(String text, {int index = 0}) => _sseLine({
  'event_type': 'step.delta',
  'index': index,
  'delta': {'type': 'text', 'text': text},
});

String _completed({Map<String, dynamic>? usage, String status = 'completed'}) =>
    _sseLine({
      'event_type': 'interaction.completed',
      'interaction': {'id': 'int_1', 'status': status, 'usage': ?usage},
    });

void main() {
  group('GeminiStreamConverter', () {
    test('emits text deltas as assistant content', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.start',
            'index': 0,
            'step': {'type': 'model_output'},
          }) +
          _textDelta('Hello ') +
          _textDelta('world') +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      final content = chunks.map((c) => c.message?.content ?? '').join();
      expect(content, 'Hello world');
      expect(chunks.last.done, isTrue);
    });

    test('separates thought_summary from text', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {
              'type': 'thought_summary',
              'content': {'type': 'text', 'text': 'Considering options.'},
            },
          }) +
          _textDelta('Answer', index: 1) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      final thinking = chunks.map((c) => c.message?.thinking ?? '').join();
      final content = chunks.map((c) => c.message?.content ?? '').join();

      expect(thinking, 'Considering options.');
      expect(content, 'Answer');
      // Thinking must never leak into content.
      expect(content, isNot(contains('Considering')));
    });

    test('resolves the model reported by interaction.created', () async {
      final body =
          _created(model: 'gemini-3.6-flash') + _textDelta('Hi') + _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.first.model, 'gemini-3.6-flash');
    });

    test('concatenates arguments_delta fragments into a tool call', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.start',
            'index': 0,
            'step': {
              'type': 'function_call',
              'id': 'call_abc123',
              'name': 'get_weather',
              'arguments': <String, dynamic>{},
            },
          }) +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {'type': 'arguments_delta', 'arguments': '{"city"'},
          }) +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {'type': 'arguments_delta', 'arguments': ': "Oslo"}'},
          }) +
          _sseLine({'event_type': 'step.stop', 'index': 0}) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      final toolChunk = chunks.firstWhere(
        (c) => c.message?.toolCalls?.isNotEmpty == true,
      );
      final toolCall = toolChunk.message!.toolCalls!.first;
      expect(toolCall.id, 'call_abc123'); // server id, not synthesized
      expect(toolCall.name, 'get_weather');
      expect(json.decode(toolCall.arguments), {'city': 'Oslo'});
      // Tool calls arrive before the terminal done chunk.
      expect(toolChunk.done, isFalse);
      expect(chunks.last.done, isTrue);
    });

    test('reports toolCalls finish reason when a function call ran', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.start',
            'index': 0,
            'step': {'type': 'function_call', 'id': 'c1', 'name': 'echo'},
          }) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.last.finishReason, LLMFinishReason.toolCalls);
    });

    test('maps completed status to a stop finish reason', () async {
      final body = _created() + _textDelta('Hi') + _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.last.finishReason, LLMFinishReason.stop);
    });

    test('maps Interactions usage field names', () async {
      final body =
          _created() +
          _textDelta('Hi') +
          _completed(
            usage: {
              'total_tokens': 130,
              'total_input_tokens': 80,
              'total_output_tokens': 40,
              'total_cached_tokens': 5,
              'total_thought_tokens': 10,
              'total_tool_use_tokens': 2,
            },
          );

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      final done = chunks.last;
      expect(done.promptEvalCount, 80);
      expect(done.evalCount, 40);
      expect(done.usage?.promptTokens, 80);
      expect(done.usage?.completionTokens, 40);
      expect(done.usage?.totalTokens, 130);
      expect(done.providerMetadata['total_tokens'], 130);
      expect(done.providerMetadata['total_thought_tokens'], 10);
      expect(done.providerMetadata['total_cached_tokens'], 5);
      expect(done.providerMetadata['total_tool_use_tokens'], 2);
      expect(done.providerMetadata['interaction_id'], 'int_1');
    });

    test('falls back to cumulative usage from step.stop', () async {
      final body =
          _created() +
          _textDelta('Hi') +
          _sseLine({
            'event_type': 'step.stop',
            'index': 0,
            'usage': {'total_input_tokens': 7, 'total_output_tokens': 3},
            'step_usage': {'total_output_tokens': 3},
          }) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.last.promptEvalCount, 7);
      expect(chunks.last.evalCount, 3);
    });

    test('accumulates thought_signature per step index', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {'type': 'thought_signature', 'signature': 'abc'},
          }) +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {'type': 'thought_signature', 'signature': 'def'},
          }) +
          _sseLine({
            'event_type': 'step.delta',
            'index': 1,
            'delta': {'type': 'thought_signature', 'signature': 'xyz'},
          }) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.last.providerMetadata['thought_signatures'], {
        '0': 'abcdef',
        '1': 'xyz',
      });
    });

    test('emits image deltas as data URIs', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'step.delta',
            'index': 0,
            'delta': {
              'type': 'image',
              'mime_type': 'image/png',
              'data': 'iVBORw0KGgo',
            },
          }) +
          _completed();

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      final imageChunk = chunks.firstWhere(
        (c) => c.message?.images?.isNotEmpty == true,
      );
      expect(
        imageChunk.message!.images!.first,
        'data:image/png;base64,iVBORw0KGgo',
      );
    });

    test('throws LLMApiException on an error event', () async {
      final body =
          _created() +
          _sseLine({
            'event_type': 'error',
            'error': {'message': 'Invalid API key', 'code': 401},
          });

      expect(
        () => GeminiStreamConverter.toLLMStream(
          _makeResponse(body),
          model: 'gemini-3.5-flash-lite',
        ).toList(),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.message, 'message', 'Invalid API key')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('stops at the terminating done event', () async {
      final body =
          '${_created()}${_textDelta('Hi')}${_completed()}'
          'event: done\ndata: [DONE]\n';

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(chunks.where((c) => c.done == true).length, 1);
    });

    test('skips comment and non-data lines', () async {
      final body =
          ': keep-alive\n${_created()}${_textDelta('Content')}${_completed()}';

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-3.5-flash-lite',
      ).toList();

      expect(
        chunks.where((c) => c.message?.content?.isNotEmpty == true).length,
        1,
      );
    });
  });
}
