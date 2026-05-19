import 'dart:convert';

/// Incrementally decodes UTF-8 bytes from llama.cpp token pieces.
///
/// Some tokenizers can split a single UTF-8 scalar across multiple generated
/// tokens. Decoding each token piece independently can therefore throw
/// [FormatException] for an unfinished byte sequence. This decoder keeps the
/// partial sequence buffered until the next piece arrives.
class StreamingUtf8Decoder {
  StreamingUtf8Decoder() {
    _stringSink = _CollectingStringSink();
    _byteSink = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_stringSink));
  }

  late final _CollectingStringSink _stringSink;
  late final ByteConversionSink _byteSink;
  var _isClosed = false;

  /// Adds a token-piece byte sequence and returns any newly completed text.
  String add(List<int> bytes) {
    if (_isClosed) {
      throw StateError('Cannot add bytes after closing decoder');
    }
    if (bytes.isEmpty) {
      return '';
    }

    _byteSink.add(bytes);
    return _stringSink.take();
  }

  /// Flushes remaining buffered bytes and returns final decoded text, if any.
  String close() {
    if (!_isClosed) {
      _byteSink.close();
      _isClosed = true;
    }
    return _stringSink.take();
  }
}

class _CollectingStringSink implements StringSink {
  final _chunks = <String>[];

  @override
  void write(Object? object) {
    _chunks.add(object.toString());
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    _chunks.add(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    _chunks.add(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  String take() {
    if (_chunks.isEmpty) {
      return '';
    }

    final result = _chunks.join();
    _chunks.clear();
    return result;
  }
}
