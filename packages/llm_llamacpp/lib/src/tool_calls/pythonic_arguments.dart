import 'dart:convert';

/// One parsed Pythonic call: a function name plus its keyword arguments.
class PythonicCall {
  /// Creates a parsed Pythonic call.
  PythonicCall({required this.name, required this.arguments});

  /// The function name.
  final String name;

  /// The keyword arguments, already converted to JSON-compatible Dart values.
  final Map<String, dynamic> arguments;

  /// The arguments encoded as a JSON string, as [LLMToolCall] expects.
  String get argumentsJson => json.encode(arguments);
}

/// Parses the Pythonic tool-call syntax used by LFM2/LFM2.5 and Llama 3.x.
///
/// The payload is a bracketed list of calls:
///
/// ```
/// [get_weather(city='Oslo', days=3), get_time(tz=None)]
/// ```
///
/// Value syntax follows what the LFM2.5 chat template emits (its
/// `format_arg_value` macro): strings are single-quoted with `\\`, `\'`, `\n`
/// and `\r` escaped, collections are rendered as JSON, and everything else goes
/// through Python's `str()` — so booleans arrive as `True`/`False` and null as
/// `None`. Double-quoted strings and JSON `true`/`false`/`null` are accepted too,
/// because models mix the two in practice.
///
/// Returns an empty list when [source] does not parse. This is deliberately
/// total rather than throwing: a half-written call mid-stream is normal, and the
/// caller simply keeps buffering.
List<PythonicCall> parsePythonicCallList(
  String source, {
  bool lenient = false,
}) {
  final scanner = _Scanner(source, lenient: lenient);
  try {
    return scanner.parseCallList();
  } on FormatException {
    return const [];
  }
}

/// Whether [content] plausibly contains a bare Pythonic call list.
///
/// Used to distinguish `[get_time()]` from ordinary prose that happens to
/// contain brackets. Intentionally conservative: it requires a complete,
/// fully-parsable call list, so a stray `[1, 2, 3]` or a markdown link does not
/// register.
bool looksLikePythonicCallList(String content) {
  final start = content.indexOf('[');
  if (start < 0) return false;
  final end = content.lastIndexOf(']');
  if (end <= start) return false;
  final calls = parsePythonicCallList(content.substring(start, end + 1));
  return calls.isNotEmpty;
}

/// A recursive-descent scanner over the Pythonic value grammar.
class _Scanner {
  _Scanner(this.src, {required this.lenient});

  final String src;

  /// When set, tolerate malformed calls that real models emit — a missing
  /// opening paren (`fn a=1)`) and stray trailing parens. Only enabled when the
  /// text arrived inside an explicit tool-call delimiter, where we already know
  /// the model intended a call and guessing cannot produce a false positive.
  final bool lenient;

  int pos = 0;

  bool get atEnd => pos >= src.length;
  String get current => src[pos];

  void skipWhitespace() {
    while (!atEnd &&
        (current == ' ' ||
            current == '\n' ||
            current == '\r' ||
            current == '\t')) {
      pos++;
    }
  }

  Never fail(String message) =>
      throw FormatException('$message at offset $pos', src, pos);

  void expect(String ch) {
    skipWhitespace();
    if (atEnd || current != ch) fail("expected '$ch'");
    pos++;
  }

  List<PythonicCall> parseCallList() {
    skipWhitespace();
    // The bracket wrapper is optional: LFM2 emits `[fn()]`, while Llama's
    // python_tag emits a single bare `fn()`.
    final bracketed = !atEnd && current == '[';
    if (bracketed) pos++;

    final calls = <PythonicCall>[];
    skipWhitespace();
    while (!atEnd) {
      skipWhitespace();
      if (lenient) {
        // Step over stray closing parens. Real LFM2.5 output has produced
        // `[calculator arguments='multiply', a=347, b=89)]`, where the call is
        // missing its opening paren but still carries the closing one.
        while (!atEnd && current == ')') {
          pos++;
          skipWhitespace();
        }
      }
      if (bracketed && !atEnd && current == ']') {
        pos++;
        break;
      }
      if (atEnd) break;
      calls.add(parseCall());
      skipWhitespace();
      if (!atEnd && current == ',') {
        pos++;
        continue;
      }
      if (bracketed && !atEnd && current == ']') {
        pos++;
        break;
      }
      if (!bracketed) break;
      if (atEnd) {
        // Unterminated list: incomplete, not a parse we should trust.
        fail('unterminated call list');
      }
    }

    skipWhitespace();
    if (lenient) {
      // Tolerate the stray trailing `)` seen from real LFM2.5 output.
      while (!atEnd && (current == ')' || current == ']')) {
        pos++;
        skipWhitespace();
      }
    }
    if (calls.isEmpty) fail('no calls found');
    if (!atEnd) fail('trailing input');
    return calls;
  }

  PythonicCall parseCall() {
    skipWhitespace();
    final name = parseIdentifier();
    skipWhitespace();

    if (atEnd || current != '(') {
      if (!lenient) fail("expected '(' after function name");
      // Malformed-but-intended form: `fn a=1, b=2)`.
      final args = parseArgumentsUntilCloseOrEnd();
      return PythonicCall(name: name, arguments: args);
    }

    pos++; // consume '('
    final args = <String, dynamic>{};
    skipWhitespace();
    if (!atEnd && current == ')') {
      pos++;
      return PythonicCall(name: name, arguments: args);
    }
    while (true) {
      skipWhitespace();
      final key = parseIdentifier();
      expect('=');
      args[key] = parseValue();
      skipWhitespace();
      if (!atEnd && current == ',') {
        pos++;
        skipWhitespace();
        // Allow a trailing comma before the closing paren.
        if (!atEnd && current == ')') {
          pos++;
          break;
        }
        continue;
      }
      if (!atEnd && current == ')') {
        pos++;
        break;
      }
      fail("expected ',' or ')' in argument list");
    }
    return PythonicCall(name: name, arguments: args);
  }

  Map<String, dynamic> parseArgumentsUntilCloseOrEnd() {
    final args = <String, dynamic>{};
    while (true) {
      skipWhitespace();
      if (atEnd || current == ')' || current == ']') break;
      final key = parseIdentifier();
      expect('=');
      args[key] = parseValue();
      skipWhitespace();
      if (!atEnd && current == ',') {
        pos++;
        continue;
      }
      break;
    }
    return args;
  }

  String parseIdentifier() {
    skipWhitespace();
    final start = pos;
    while (!atEnd) {
      final c = current;
      final isWordChar =
          (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) ||
          (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) ||
          (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) ||
          c == '_' ||
          // Namespaced tool names such as `server.get_time`.
          c == '.' ||
          c == '-';
      if (!isWordChar) break;
      pos++;
    }
    if (pos == start) fail('expected identifier');
    return src.substring(start, pos);
  }

  dynamic parseValue() {
    skipWhitespace();
    if (atEnd) fail('expected value');

    switch (current) {
      case "'":
      case '"':
        return parseString();
      case '[':
        return parseList();
      case '{':
        return parseMap();
    }

    // Bare word: a literal, or a number.
    final start = pos;
    while (!atEnd &&
        current != ',' &&
        current != ')' &&
        current != ']' &&
        current != '}' &&
        current != ' ') {
      pos++;
    }
    final raw = src.substring(start, pos).trim();
    if (raw.isEmpty) fail('expected value');

    switch (raw) {
      case 'True':
      case 'true':
        return true;
      case 'False':
      case 'false':
        return false;
      case 'None':
      case 'null':
        return null;
    }

    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(raw);
    if (asDouble != null) return asDouble;

    // An unquoted string. Models emit these when they drop the quotes; keeping
    // it as text is more useful than failing the whole call.
    return raw;
  }

  String parseString() {
    final quote = current;
    pos++;
    final buffer = StringBuffer();
    while (true) {
      if (atEnd) fail('unterminated string');
      final c = current;
      if (c == r'\') {
        pos++;
        if (atEnd) fail('dangling escape');
        final esc = current;
        pos++;
        switch (esc) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case 'u':
            if (pos + 4 > src.length) fail('truncated \\u escape');
            final hex = src.substring(pos, pos + 4);
            final code = int.tryParse(hex, radix: 16);
            if (code == null) fail('bad \\u escape');
            buffer.writeCharCode(code);
            pos += 4;
          default:
            // Covers \\ , \' and \" — and anything else passes through, which
            // matches Python's behaviour for unknown escapes.
            buffer.write(esc);
        }
        continue;
      }
      if (c == quote) {
        pos++;
        return buffer.toString();
      }
      buffer.write(c);
      pos++;
    }
  }

  List<dynamic> parseList() {
    expect('[');
    final items = <dynamic>[];
    skipWhitespace();
    if (!atEnd && current == ']') {
      pos++;
      return items;
    }
    while (true) {
      items.add(parseValue());
      skipWhitespace();
      if (!atEnd && current == ',') {
        pos++;
        skipWhitespace();
        if (!atEnd && current == ']') {
          pos++;
          return items;
        }
        continue;
      }
      expect(']');
      return items;
    }
  }

  Map<String, dynamic> parseMap() {
    expect('{');
    final map = <String, dynamic>{};
    skipWhitespace();
    if (!atEnd && current == '}') {
      pos++;
      return map;
    }
    while (true) {
      skipWhitespace();
      final key = (current == "'" || current == '"')
          ? parseString()
          : parseIdentifier();
      expect(':');
      map[key] = parseValue();
      skipWhitespace();
      if (!atEnd && current == ',') {
        pos++;
        skipWhitespace();
        if (!atEnd && current == '}') {
          pos++;
          return map;
        }
        continue;
      }
      expect('}');
      return map;
    }
  }
}
