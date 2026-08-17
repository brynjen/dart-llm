import 'dart:async';

/// Stream transformer for decoding OpenAI SSE (Server-Sent Events) streams.
class GPTStreamDecoder {
  /// Returns a stream transformer that decodes SSE data events.
  ///
  /// Buffers partial lines across transport chunks: an SSE event routinely
  /// arrives split mid-line over the network, and without the buffer both
  /// halves fail the `data:`/JSON checks and the event is silently dropped —
  /// live streams then lose almost every frame while single-chunk test
  /// fixtures pass.
  static StreamTransformer<String, String> get decoder {
    var buffer = '';
    return StreamTransformer<String, String>.fromHandlers(
      handleData: (chunk, sink) {
        buffer += chunk;
        while (true) {
          final newline = buffer.indexOf('\n');
          if (newline == -1) break;
          final line = buffer.substring(0, newline);
          buffer = buffer.substring(newline + 1);
          _emitLine(line, sink);
        }
      },
      handleDone: (sink) {
        // Flush a trailing line that arrived without a final newline.
        _emitLine(buffer, sink);
        sink.close();
      },
    );
  }

  static void _emitLine(String line, EventSink<String> sink) {
    if (!line.startsWith('data:')) return;
    final content = line.substring(5).trim();
    if (content == '[DONE]') {
      sink.add('[DONE]');
      return;
    }
    // Only add non-empty content that looks like complete JSON.
    if (content.isNotEmpty &&
        content.startsWith('{') &&
        _isCompleteJson(content)) {
      sink.add(content);
    }
  }

  /// Basic check to see if JSON looks complete.
  static bool _isCompleteJson(String content) {
    if (!content.startsWith('{') || !content.endsWith('}')) {
      return false;
    }

    int braceCount = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < content.length; i++) {
      final char = content[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == '{') {
          braceCount++;
        } else if (char == '}') {
          braceCount--;
        }
      }
    }

    return braceCount == 0 && !inString;
  }
}
