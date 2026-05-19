import 'dart:convert';

import 'package:llm_llamacpp/src/streaming_utf8_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('StreamingUtf8Decoder', () {
    test('buffers unfinished multi-byte sequences across chunks', () {
      final decoder = StreamingUtf8Decoder();
      final bytes = utf8.encode('A 😀 philosopher');

      expect(decoder.add(bytes.sublist(0, 3)), 'A ');
      expect(decoder.add(bytes.sublist(3, 4)), '');
      expect(decoder.add(bytes.sublist(4, 5)), '');
      expect(decoder.add(bytes.sublist(5, 6)), '😀');
      expect(decoder.add(bytes.sublist(6, 7)), ' ');
      expect(decoder.add(bytes.sublist(7)), 'philosopher');
      expect(decoder.close(), '');
    });

    test('flushes an unfinished final sequence as replacement text', () {
      final decoder = StreamingUtf8Decoder();

      expect(decoder.add([0xF0]), '');
      expect(decoder.close(), '\uFFFD');
    });
  });
}
