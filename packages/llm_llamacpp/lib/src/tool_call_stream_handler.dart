import 'package:llm_core/llm_core.dart'
    show LLMLogger, LLMLogLevel, LLMToolCall;
import 'package:llm_llamacpp/src/tool_call_parser.dart';
import 'package:llm_llamacpp/src/tool_calls/tool_call_syntax.dart';

/// Result of processing a token in the stream handler.
class StreamHandlerResult {
  /// Creates a stream handler result.
  StreamHandlerResult({required this.shouldYield, this.content});

  /// Whether the content should be yielded to the user.
  final bool shouldYield;

  /// The content to yield (if shouldYield is true).
  final String? content;
}

/// Handles tool call detection and buffering during token streaming.
///
/// Two things have to be true at once while streaming: a tool call must never be
/// shown to the user as text, and ordinary prose must reach them without being
/// held back. The handler therefore stays in pass-through mode until it sees
/// something that could begin a tool call, and only then starts buffering.
///
/// "Could begin a tool call" includes a *partial* delimiter. Delimiters do not
/// necessarily arrive as one token — `<|tool_call_start|>` happens to be a single
/// token for LFM2.5, but `<tool_call>` is usually several — so a suffix of the
/// pending text that is a prefix of any known delimiter is held back rather than
/// emitted. Without that, the leading `<` of a tool call is shown to the user a
/// moment before the rest of the call is recognised and suppressed.
class ToolCallStreamHandler {
  /// Creates a stream handler.
  ToolCallStreamHandler({required this.logger, required this.tools});

  /// Logger for diagnostics.
  final LLMLogger logger;

  /// Available tools. Typed as `List` to avoid a circular import.
  final List tools;

  String _accumulatedContent = '';
  final List<LLMToolCall> _collectedToolCalls = [];

  /// Text held back because it might be, or might be part of, a tool call.
  String _pendingContent = '';

  /// True once we have seen a complete opening delimiter (or a bare `{`) and are
  /// waiting for the call to complete.
  bool _inPotentialToolCall = false;

  /// The accumulated content from all tokens processed so far.
  String get accumulatedContent => _accumulatedContent;

  /// The tool calls collected during streaming.
  List<LLMToolCall> get collectedToolCalls =>
      List.unmodifiable(_collectedToolCalls);

  /// Markers that can begin a tool call.
  ///
  /// The bare `{` and `[` keep the pre-existing behaviour for models that emit
  /// undelimited JSON or Pythonic calls because the prompt asked them to.
  static final List<String> _openers = [
    ...ToolCallFormat.openingDelimiters,
    '{',
    '[',
  ];

  /// Process a token from the stream.
  ///
  /// Returns a [StreamHandlerResult] indicating whether to yield content, and
  /// what to yield.
  StreamHandlerResult processToken(String token) {
    _accumulatedContent += token;
    _pendingContent += token;

    if (!_inPotentialToolCall) {
      final openerAt = _firstOpenerIndex(_pendingContent);
      if (openerAt == null) {
        // Nothing that could start a call — but the tail may be the beginning of
        // a delimiter, so hold that much back and release the rest.
        final keep = _danglingPrefixLength(_pendingContent);
        final release = _pendingContent.substring(
          0,
          _pendingContent.length - keep,
        );
        _pendingContent = _pendingContent.substring(
          _pendingContent.length - keep,
        );
        return release.isEmpty
            ? StreamHandlerResult(shouldYield: false)
            : StreamHandlerResult(shouldYield: true, content: release);
      }

      // Release any plain text that preceded the opener, then start buffering.
      final prefix = _pendingContent.substring(0, openerAt);
      _pendingContent = _pendingContent.substring(openerAt);
      _inPotentialToolCall = true;
      logger.fine('Detected potential tool call start');
      if (prefix.isNotEmpty) {
        return StreamHandlerResult(shouldYield: true, content: prefix);
      }
      return StreamHandlerResult(shouldYield: false);
    }

    // Buffering: try to resolve as soon as the buffer could hold a whole call.
    if (!_looksComplete(_pendingContent)) {
      return StreamHandlerResult(shouldYield: false);
    }

    final toolCalls = ToolCallParser.parseToolCalls(_pendingContent);
    if (toolCalls.isNotEmpty) {
      logger.info('Found ${toolCalls.length} tool calls in buffered content');
      _collectedToolCalls.addAll(toolCalls);
      // Swallow the call text; the user should never see it.
      _pendingContent = '';
      _inPotentialToolCall = false;
      return StreamHandlerResult(shouldYield: false);
    }

    // A false alarm: it looked like a call but did not parse as one. Give the
    // buffered text back to the user.
    logger.fine('Not a valid tool call, yielding buffered content');
    final contentToYield = _pendingContent;
    _pendingContent = '';
    _inPotentialToolCall = false;
    return StreamHandlerResult(shouldYield: true, content: contentToYield);
  }

  /// Index of the earliest complete opener in [text], or null if there is none.
  static int? _firstOpenerIndex(String text) {
    int? best;
    for (final opener in _openers) {
      final at = text.indexOf(opener);
      if (at >= 0 && (best == null || at < best)) best = at;
    }
    return best;
  }

  /// Length of the trailing run of [text] that is a strict prefix of an opener.
  ///
  /// Held back so a delimiter split across tokens is never partly emitted.
  static int _danglingPrefixLength(String text) {
    final maxLen = _openers
        .map((o) => o.length)
        .reduce((a, b) => a > b ? a : b);
    final limit = text.length < maxLen - 1 ? text.length : maxLen - 1;
    for (var len = limit; len > 0; len--) {
      final tail = text.substring(text.length - len);
      for (final opener in _openers) {
        if (opener.length > tail.length && opener.startsWith(tail)) {
          return len;
        }
      }
    }
    return 0;
  }

  /// Whether [buffer] plausibly contains a whole tool call yet.
  ///
  /// Resolving too early would emit a half-written call as prose; resolving too
  /// late would stall the stream. For delimited formats the closing delimiter is
  /// the signal. For the bare formats, balanced brackets are.
  bool _looksComplete(String buffer) {
    for (final f in ToolCallFormat.delimited) {
      final (open, close) = f.delimiters!;
      if (!buffer.startsWith(open)) continue;
      // No closing delimiter to wait for: settle up at end of stream instead.
      if (close.isEmpty) return false;
      return buffer.contains(close);
    }

    // Bare `{...}` or `[...]`.
    final opener = buffer.isEmpty ? '' : buffer[0];
    if (opener == '{') {
      return ToolCallParser.countBraces(buffer) == 0 && buffer.contains('}');
    }
    if (opener == '[') {
      return _bracketsBalanced(buffer) && buffer.contains(']');
    }
    return false;
  }

  static bool _bracketsBalanced(String s) {
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '[') depth++;
      if (s[i] == ']') depth--;
    }
    return depth == 0;
  }

  /// Finalize processing and check for any remaining tool calls.
  ///
  /// Returns any remaining buffered content that should be yielded.
  String? finalize({required bool hasTools}) {
    String? remainingContent;

    if (_pendingContent.isNotEmpty) {
      // Last chance for the open-ended formats (Mistral, python_tag) and for a
      // call the model left unterminated.
      final trailing = hasTools
          ? ToolCallParser.parseToolCalls(_pendingContent)
          : const <LLMToolCall>[];
      if (trailing.isNotEmpty) {
        logger.info('Found ${trailing.length} tool calls in trailing buffer');
        _collectedToolCalls.addAll(trailing);
      } else {
        logger.fine('Yielding remaining buffered content');
        remainingContent = _pendingContent;
      }
      _pendingContent = '';
      _inPotentialToolCall = false;
    }

    // Check the full response if streaming found nothing — covers calls whose
    // delimiters straddled a buffer flush.
    if (hasTools && _collectedToolCalls.isEmpty) {
      logger.fine('Parsing tool calls from full response...');
      final parsedToolCalls = ToolCallParser.parseToolCalls(
        _accumulatedContent,
      );
      logger.info('Found ${parsedToolCalls.length} tool calls');
      if (logger.isLoggable(LLMLogLevel.fine)) {
        for (final tc in parsedToolCalls) {
          logger.fine('  - Tool: ${tc.name}, Args: ${tc.arguments}');
        }
      }
      if (parsedToolCalls.isNotEmpty) {
        _collectedToolCalls.addAll(parsedToolCalls);
        // Whatever was still buffered is a fragment of the call we just matched
        // against the full response (typically an unterminated delimiter that
        // could not parse on its own), so drop it rather than render markup.
        remainingContent = null;
      }
    }

    return remainingContent;
  }
}
