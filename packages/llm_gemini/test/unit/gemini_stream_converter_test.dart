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

Map<String, dynamic> _textCandidate(String text, {String? finishReason}) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      if (finishReason != null) 'finishReason': finishReason,
    },
  ],
};

void main() {
  group('GeminiStreamConverter', () {
    test('emits text content chunk', () async {
      final body = _sseLine(_textCandidate('Hello world'));

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-2.0-flash',
      ).toList();

      expect(chunks, isNotEmpty);
      final contentChunk = chunks.first;
      expect(contentChunk.message?.content, 'Hello world');
      expect(contentChunk.done, false);
    });

    test('emits done chunk when finishReason is STOP', () async {
      final body =
          _sseLine(_textCandidate('Hi')) +
          _sseLine({
            ..._textCandidate('', finishReason: 'STOP'),
            'usageMetadata': {
              'promptTokenCount': 10,
              'candidatesTokenCount': 5,
            },
          });

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-2.0-flash',
      ).toList();

      final done = chunks.lastWhere((c) => c.done == true);
      expect(done.done, true);
      expect(done.promptEvalCount, 10);
      expect(done.evalCount, 5);
    });

    test('emits tool call chunk for functionCall parts', () async {
      final body = _sseLine({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {
                  'functionCall': {
                    'name': 'get_weather',
                    'args': {'city': 'Oslo'},
                  },
                },
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': {'promptTokenCount': 8, 'candidatesTokenCount': 4},
      });

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-2.0-flash',
      ).toList();

      final toolChunk = chunks.firstWhere(
        (c) => c.message?.toolCalls?.isNotEmpty == true,
        orElse: () => throw StateError('no tool chunk'),
      );
      final toolCall = toolChunk.message!.toolCalls!.first;
      expect(toolCall.name, 'get_weather');
      final args = json.decode(toolCall.arguments) as Map;
      expect(args['city'], 'Oslo');
    });

    test('throws LLMApiException on error in stream', () async {
      final body = _sseLine({
        'error': {
          'code': 400,
          'message': 'Invalid API key',
          'status': 'UNAUTHENTICATED',
        },
      });

      expect(
        () => GeminiStreamConverter.toLLMStream(
          _makeResponse(body),
          model: 'gemini-2.0-flash',
        ).toList(),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('skips non-data lines', () async {
      final body = ': keep-alive\n${_sseLine(_textCandidate('Content'))}\n';

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-2.0-flash',
      ).toList();

      expect(
        chunks.where((c) => c.message?.content?.isNotEmpty == true).length,
        1,
      );
    });

    test('uses provided model name', () async {
      final body = _sseLine(_textCandidate('Hi'));

      final chunks = await GeminiStreamConverter.toLLMStream(
        _makeResponse(body),
        model: 'gemini-1.5-pro',
      ).toList();

      expect(chunks.first.model, 'gemini-1.5-pro');
    });
  });
}
