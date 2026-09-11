import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/ollama_stream_converter.dart';
import 'package:test/test.dart';

void main() {
  _toolCallTurnTests();

  group('OllamaStreamConverter', () {
    test('parses NDJSON split across transport chunk boundaries', () async {
      final frame1 = json.encode({
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'message': {'role': 'assistant', 'content': 'Hel'},
        'done': false,
      });
      final frame2 = json.encode({
        'model': 'qwen3:0.6b',
        'created_at': '2024-01-01T00:00:00.100Z',
        'message': {'role': 'assistant', 'content': 'lo'},
        'done': true,
      });

      final bytes = utf8.encode('$frame1\n$frame2\n');
      final splitIndex = bytes.length ~/ 2;
      final chunks = <List<int>>[
        bytes.sublist(0, splitIndex),
        bytes.sublist(splitIndex),
      ];

      final response = http.StreamedResponse(Stream.fromIterable(chunks), 200);
      final parsed = await OllamaStreamConverter.toLLMStream(response).toList();

      expect(parsed.length, 2);
      expect(parsed.first.message?.content, 'Hel');
      expect(parsed.last.message?.content, 'lo');
      expect(parsed.last.done, isTrue);
    });

    test('throws immediately when stream frame contains error', () async {
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"model does not support chat"}\n')),
        200,
      );

      expect(
        () async => OllamaStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('Ollama stream error: model does not support chat'),
          ),
        ),
      );
    });

    test('throws after malformed-line retry budget is exceeded', () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode('not-json-1\nnot-json-2\nnot-json-3\nnot-json-4\n'),
        ),
        200,
      );

      expect(
        () async => OllamaStreamConverter.toLLMStream(response).toList(),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('Failed to parse Ollama NDJSON stream'),
          ),
        ),
      );
    });
  });
}

void _toolCallTurnTests() {
  /// The exact two-frame shape captured from Ollama's native `/api/chat`
  /// against qwen3:8b: the complete call arrives on a non-terminal frame, and
  /// the terminal frame reports `stop` and carries no calls at all.
  String capturedToolCallTurn() => [
    json.encode({
      'model': 'qwen3:8b',
      'created_at': '2026-09-11T10:00:00.000Z',
      'message': {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call_3ud5qy0o',
            'function': {
              'index': 0,
              'name': 'get_weather',
              'arguments': {'city': 'Oslo'},
            },
          },
        ],
      },
      'done': false,
    }),
    json.encode({
      'model': 'qwen3:8b',
      'created_at': '2026-09-11T10:00:01.000Z',
      'message': {'role': 'assistant', 'content': ''},
      'done': true,
      'done_reason': 'stop',
      'prompt_eval_count': 120,
      'eval_count': 18,
    }),
  ].map((line) => '$line\n').join();

  group('OllamaStreamConverter tool-call turns', () {
    test('a turn that called a tool is reported as a tool-call turn', () async {
      // `done_reason` is `stop` on every Ollama turn, tool call or not, and the
      // calls land on the frame before the terminal one. Reading the terminal
      // frame in isolation therefore always said `stop`, which contradicts the
      // calls the same turn produced.
      final response = http.StreamedResponse(
        Stream.value(utf8.encode(capturedToolCallTurn())),
        200,
      );

      final parsed = await OllamaStreamConverter.toLLMStream(response).toList();

      expect(parsed.last.done, isTrue);
      expect(parsed.last.finishReason, LLMFinishReason.toolCalls);
      // The calls themselves still arrive where Ollama put them.
      expect(parsed.first.message?.toolCalls?.single.name, 'get_weather');
      // Token counts on the terminal frame must survive the rebuild.
      expect(parsed.last.promptEvalCount, 120);
      expect(parsed.last.evalCount, 18);
    });

    test('a turn without tool calls keeps its reported reason', () async {
      final plain = json.encode({
        'model': 'qwen3:8b',
        'created_at': '2026-09-11T10:00:00.000Z',
        'message': {'role': 'assistant', 'content': 'Hello'},
        'done': true,
        'done_reason': 'stop',
      });
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('$plain\n')),
        200,
      );

      final parsed = await OllamaStreamConverter.toLLMStream(response).toList();
      expect(parsed.last.finishReason, LLMFinishReason.stop);
    });
  });
}
