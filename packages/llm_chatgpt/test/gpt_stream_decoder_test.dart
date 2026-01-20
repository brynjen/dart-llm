import 'dart:async';

import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  group('GPTStreamDecoder', () {
    test('decodes valid SSE data events', () async {
      final input = Stream.fromIterable([
        'data: {"id": "chatcmpl-123", "model": "gpt-4o"}\n',
        'data: {"id": "chatcmpl-123", "choices": []}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 2);
      expect(results[0], '{"id": "chatcmpl-123", "model": "gpt-4o"}');
      expect(results[1], '{"id": "chatcmpl-123", "choices": []}');
    });

    test('handles multiple data events in one chunk', () async {
      final input = Stream.fromIterable([
        'data: {"id": "1"}\ndata: {"id": "2"}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 2);
      expect(results[0], '{"id": "1"}');
      expect(results[1], '{"id": "2"}');
    });

    test('handles [DONE] marker', () async {
      final input = Stream.fromIterable([
        'data: {"id": "chatcmpl-123"}\n',
        'data: [DONE]\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 2);
      expect(results[0], '{"id": "chatcmpl-123"}');
      expect(results[1], '[DONE]');
    });

    test('filters incomplete JSON', () async {
      final input = Stream.fromIterable([
        'data: {"id": "chatcmpl-123", "model": "gpt-4o"\n', // Missing closing brace
        'data: {"id": "chatcmpl-123"}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      // Incomplete JSON should be filtered
      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('filters non-JSON content', () async {
      final input = Stream.fromIterable([
        'data: not json\n',
        'data: {"id": "chatcmpl-123"}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('handles empty lines', () async {
      final input = Stream.fromIterable([
        '\n',
        'data: {"id": "chatcmpl-123"}\n',
        '\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('handles malformed SSE format', () async {
      final input = Stream.fromIterable([
        'notdata: {"id": "chatcmpl-123"}\n',
        'data: {"id": "chatcmpl-123"}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('handles nested JSON objects', () async {
      final input = Stream.fromIterable([
        'data: {"nested": {"value": 42}, "array": [1, 2, 3]}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"nested": {"value": 42}, "array": [1, 2, 3]}');
    });

    test('handles JSON with escaped characters', () async {
      final input = Stream.fromIterable([
        'data: {"content": "Hello\\nWorld", "quote": "He said \\"hi\\""}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], contains('Hello\\nWorld'));
      expect(results[0], contains('He said \\"hi\\"'));
    });

    test('handles multiple chunks with partial JSON', () async {
      final input = Stream.fromIterable([
        'data: {"id": "chatcmpl-123", "model": "gpt-4o"\n', // Incomplete
        'data: {"id": "chatcmpl-123"}\n', // Complete
        'data: {"id": "chatcmpl-124", "choices": [\n', // Incomplete
        'data: {"id": "chatcmpl-125"}\n', // Complete
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      // Only complete JSON objects should pass through
      expect(results.length, 2);
      expect(results[0], '{"id": "chatcmpl-123"}');
      expect(results[1], '{"id": "chatcmpl-125"}');
    });

    test('handles empty data events', () async {
      final input = Stream.fromIterable([
        'data: \n',
        'data: {"id": "chatcmpl-123"}\n',
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('handles data events with whitespace', () async {
      final input = Stream.fromIterable([
        'data:  {"id": "chatcmpl-123"}  \n', // With whitespace
      ]);

      final output = input.transform(GPTStreamDecoder.decoder);
      final results = await output.toList();

      expect(results.length, 1);
      expect(results[0], '{"id": "chatcmpl-123"}');
    });

    test('handles stream completion', () async {
      final controller = StreamController<String>();
      final input = controller.stream;
      final output = input.transform(GPTStreamDecoder.decoder);

      controller.add('data: {"id": "chatcmpl-123"}\n');
      await controller.close();

      final results = await output.toList();
      expect(results.length, 1);
    });
  });
}
