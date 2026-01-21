import 'package:llm_core/llm_core.dart' show
    LLMLogger,
    LLMLogLevel,
    LLMToolCall;
import 'package:llm_llamacpp/src/tool_call_parser.dart';

/// Result of processing a token in the stream handler.
class StreamHandlerResult {
  StreamHandlerResult({
    required this.shouldYield,
    this.content,
  });

  /// Whether the content should be yielded to the user.
  final bool shouldYield;

  /// The content to yield (if shouldYield is true).
  final String? content;
}

/// Handles tool call detection and buffering during token streaming.
///
/// This class manages the state needed to detect tool calls mid-stream,
/// buffer tokens while detecting potential JSON tool calls, and parse
/// tool calls from the accumulated content.
class ToolCallStreamHandler {
  ToolCallStreamHandler({
    required this.logger,
    required this.tools,
  });

  final LLMLogger logger;
  final List tools; // List<LLMTool> but we don't import it to avoid circular deps

  String _accumulatedContent = '';
  final List<LLMToolCall> _collectedToolCalls = [];
  String _pendingContent = '';
  bool _inPotentialToolCall = false;

  /// The accumulated content from all tokens processed so far.
  String get accumulatedContent => _accumulatedContent;

  /// The tool calls collected during streaming.
  List<LLMToolCall> get collectedToolCalls => List.unmodifiable(_collectedToolCalls);

  /// Process a token from the stream.
  ///
  /// [token] - The token to process.
  ///
  /// Returns a [StreamHandlerResult] indicating whether to yield the content
  /// and what content to yield.
  StreamHandlerResult processToken(String token) {
    _accumulatedContent += token;
    _pendingContent += token;

    // Check if we might be in a tool call
    // Look for opening brace that might start a tool call JSON
    if (!_inPotentialToolCall && _pendingContent.contains('{')) {
      _inPotentialToolCall = true;
      logger.fine('Detected potential tool call start');
    }

    // If we're in a potential tool call, buffer the content
    if (_inPotentialToolCall) {
      // Check if we have a complete JSON object
      final braceCount = ToolCallParser.countBraces(_pendingContent);
      if (braceCount == 0 && _pendingContent.contains('}')) {
        // Potential complete JSON - try to parse
        logger.fine('Potential complete JSON, trying to parse');
        final toolCalls = ToolCallParser.parseToolCalls(_pendingContent);
        if (toolCalls.isNotEmpty) {
          logger.info(
            'Found ${toolCalls.length} tool calls in buffered content',
          );
          _collectedToolCalls.addAll(toolCalls);
          // Don't yield the tool call JSON to the user
          _pendingContent = '';
          _inPotentialToolCall = false;
          return StreamHandlerResult(shouldYield: false);
        } else {
          // Not a valid tool call, yield the buffered content
          logger.fine('Not a valid tool call, yielding buffered content');
          final contentToYield = _pendingContent;
          _pendingContent = '';
          _inPotentialToolCall = false;
          return StreamHandlerResult(
            shouldYield: true,
            content: contentToYield,
          );
        }
      }
      // Keep buffering if braces aren't balanced
      return StreamHandlerResult(shouldYield: false);
    }

    // Normal token - yield immediately
    _pendingContent = '';
    return StreamHandlerResult(shouldYield: true, content: token);
  }

  /// Finalize processing and check for any remaining tool calls.
  ///
  /// [tools] - List of available tools (used to determine if we should parse).
  ///
  /// Returns any remaining buffered content that should be yielded.
  String? finalize({required bool hasTools}) {
    // Yield any remaining buffered content
    String? remainingContent;
    if (_pendingContent.isNotEmpty) {
      logger.fine('Yielding remaining buffered content');
      remainingContent = _pendingContent;
      _pendingContent = '';
    }

    // Check for tool calls in the full response if none found during streaming
    if (hasTools && _collectedToolCalls.isEmpty) {
      logger.fine('Parsing tool calls from full response...');
      final parsedToolCalls = ToolCallParser.parseToolCalls(_accumulatedContent);
      logger.info('Found ${parsedToolCalls.length} tool calls');
      if (logger.isLoggable(LLMLogLevel.fine)) {
        for (final tc in parsedToolCalls) {
          logger.fine('  - Tool: ${tc.name}, Args: ${tc.arguments}');
        }
      }
      if (parsedToolCalls.isNotEmpty) {
        _collectedToolCalls.addAll(parsedToolCalls);
      }
    }

    return remainingContent;
  }
}
