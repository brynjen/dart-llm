import 'dart:async';

/// Stream transformer for decoding OpenAI SSE (Server-Sent Events) streams.
class GPTStreamDecoder {
  /// Returns a stream transformer that decodes SSE data events.
  static StreamTransformer<String, String> get decoder {
    return StreamTransformer<String, String>.fromHandlers(
      handleData: (chunk, sink) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data:')) {
            final content = line.substring(5).trim();
            if (content == '[DONE]') {
              sink.add('[DONE]');
              continue;
            }
            // Only add non-empty content that looks like valid JSON
            if (content.isNotEmpty && content.startsWith('{')) {
              // Basic check for complete JSON object
              if (_isCompleteJson(content)) {
                sink.add(content);
              }
            }
          }
        }
      },
      handleDone: (sink) => sink.close(),
    );
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

