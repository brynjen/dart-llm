import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/dto/vllm_chunk.dart';
import 'package:llm_vllm/src/vllm_trace.dart';
import 'package:llm_vllm/src/dto/vllm_tool_call.dart';

/// Converts vLLM OpenAI-compatible SSE streaming responses to LLM chunks.
class VLLMStreamConverter {
  static const int _maxMalformedEvents = 3;

  /// Converts an HTTP streamed response to a stream of LLM chunks.
  static Stream<LLMChunk> toLLMStream(
    http.StreamedResponse response, {
    TimeoutConfig? timeoutConfig,
    int traceId = 0,
  }) async* {
    final config = timeoutConfig ?? TimeoutConfig.defaultConfig;
    final readTimeout = config.readTimeout;
    final lineBuffer = StringBuffer();
    final toolCallsByIndex = <int, VLLMToolCall>{};
    final thinkingSplitter = _ThinkingTagSplitter();
    var malformedEventCount = 0;
    // Kept so a carry flushed at end of stream can reuse the response's
    // id/model/created instead of inventing them.
    VLLMChunk? lastChunk;

    // `readTimeout` fires on the gap *between* chunks. That alone lets a
    // stream which trickles one token every few seconds run indefinitely, so
    // the total elapsed time is checked as well. `totalTimeout` is the
    // documented "maximum total time for entire request" on [TimeoutConfig].
    final totalTimeout = timeoutConfig?.totalTimeout;
    final deadline = totalTimeout == null
        ? null
        : DateTime.now().add(totalTimeout);

    var traceChunks = 0;
    vllmTrace(traceId, 'stream.read.begin');
    await for (final chunk
        in response.stream
            .transform(utf8.decoder)
            .timeout(
              readTimeout,
              // The error must be pushed into the sink, not thrown. `onTimeout`
              // runs from a timer, outside the stream's own error path, so a
              // throw here escapes as an unhandled exception and takes the
              // isolate down instead of failing this one request.
              onTimeout: (sink) {
                sink.addError(
                  TimeoutException(
                    'Stream read timed out after ${readTimeout.inSeconds} '
                    'seconds without receiving data',
                    readTimeout,
                  ),
                );
                sink.close();
              },
            )) {
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Stream exceeded the total timeout of '
          '${totalTimeout!.inSeconds} seconds. The server was still sending '
          'data; raise TimeoutConfig.totalTimeout if long responses are '
          'expected.',
          totalTimeout,
        );
      }
      traceChunks++;
      if (traceChunks == 1) vllmTrace(traceId, 'stream.firstByte');
      lineBuffer.write(chunk);
      final lines = lineBuffer.toString().split('\n');
      lineBuffer
        ..clear()
        ..write(lines.removeLast());

      for (final rawLine in lines) {
        final line = rawLine.trimRight();
        if (!line.startsWith('data:')) {
          continue;
        }

        final data = line.substring(5).trim();
        if (data.isEmpty) {
          continue;
        }
        if (data == '[DONE]') {
          vllmTrace(traceId, 'stream.done', 'chunks=$traceChunks');
          final carryChunk = _flushCarry(thinkingSplitter, lastChunk);
          if (carryChunk != null) yield carryChunk;
          return;
        }

        try {
          final decoded = json.decode(data);
          if (decoded is! Map<String, dynamic>) {
            malformedEventCount = _recordMalformedEvent(
              event: data,
              malformedEventCount: malformedEventCount,
            );
            continue;
          }
          if (decoded['error'] != null) {
            throw _streamError(decoded['error'], data);
          }

          final chunk = _splitThinkingTags(
            VLLMChunk.fromJson(decoded),
            thinkingSplitter,
          );
          lastChunk = chunk;
          _accumulateToolCalls(chunk, toolCallsByIndex);

          final choice = chunk.choices.isEmpty ? null : chunk.choices.first;
          final finishReason = choice?.finishReason;
          final hasContent = choice?.delta.content != null;
          final hasThinking = choice?.delta.thinking != null;

          if (finishReason == 'tool_calls' && toolCallsByIndex.isNotEmpty) {
            yield _toolCallChunk(chunk, toolCallsByIndex);
            toolCallsByIndex.clear();
          } else if (finishReason != null ||
              hasContent ||
              hasThinking ||
              chunk.usage != null) {
            yield chunk;
          }
          malformedEventCount = 0;
        } on LLMApiException {
          rethrow;
        } catch (_) {
          malformedEventCount = _recordMalformedEvent(
            event: data,
            malformedEventCount: malformedEventCount,
          );
        }
      }
    }

    final trailingLine = lineBuffer.toString().trimRight();
    if (trailingLine.startsWith('data:')) {
      final data = trailingLine.substring(5).trim();
      if (data.isNotEmpty && data != '[DONE]') {
        _recordMalformedEvent(
          event: data,
          malformedEventCount: malformedEventCount,
        );
      }
    }

    // Stream closed without a [DONE] sentinel (server hiccup, proxy cutoff).
    // Text held back as a potential partial <think> tag is real output at
    // this point — nothing can complete the tag anymore.
    final carryChunk = _flushCarry(thinkingSplitter, lastChunk);
    if (carryChunk != null) yield carryChunk;
  }

  /// Builds the exception for an in-stream `error` event.
  ///
  /// vLLM sends `{"error": {"message": ..., "code": 400, ...}}`; the code is
  /// surfaced as [LLMApiException.statusCode] because retry classification
  /// (`ErrorHandlers.isRetryableError`) works off the status code — without
  /// it a mid-stream 429/503 could never be recognized as retryable.
  static LLMApiException _streamError(Object error, String rawEvent) {
    final code = error is Map<String, dynamic>
        ? (error['code'] ?? error['status'])
        : null;
    final statusCode = switch (code) {
      int() => code,
      String() => int.tryParse(code),
      _ => null,
    };
    return LLMApiException(
      'vLLM stream error: $error',
      statusCode: statusCode,
      responseBody: rawEvent,
    );
  }

  /// Emits leftover splitter carry as a final synthetic chunk, or `null` when
  /// there is nothing held back.
  static VLLMChunk? _flushCarry(
    _ThinkingTagSplitter splitter,
    VLLMChunk? lastChunk,
  ) {
    final carried = splitter.flush();
    if (carried.isEmpty) return null;
    return VLLMChunk(
      id: lastChunk?.id ?? '',
      created: lastChunk?.created ?? DateTime.now(),
      model: lastChunk?.model,
      systemFingerprint: lastChunk?.systemFingerprint,
      choices: [
        VLLMChunkChoice(
          index: 0,
          delta: VLLMChunkChoiceDelta(
            role: LLMRole.assistant.name,
            content: splitter.insideThinking ? null : carried,
            thinking: splitter.insideThinking ? carried : null,
            toolCalls: null,
          ),
          logProbs: null,
          finishReason: null,
        ),
      ],
    );
  }

  static void _accumulateToolCalls(
    VLLMChunk chunk,
    Map<int, VLLMToolCall> toolCallsByIndex,
  ) {
    if (chunk.choices.isEmpty) return;
    for (final toolCall
        in chunk.choices.first.delta.toolCalls ?? const <VLLMToolCall>[]) {
      final previous = toolCallsByIndex[toolCall.index];
      if (previous == null) {
        toolCallsByIndex[toolCall.index] = toolCall;
      } else {
        toolCallsByIndex[toolCall.index] = previous.copyWith(
          newFunction: toolCall.function,
        );
      }
    }
  }

  static VLLMChunk _splitThinkingTags(
    VLLMChunk chunk,
    _ThinkingTagSplitter splitter,
  ) {
    if (chunk.choices.isEmpty) return chunk;
    final choice = chunk.choices.first;
    final content = choice.delta.content;
    if (content == null || content.isEmpty) return chunk;

    final split = splitter.split(content);
    if (split.content == content && split.thinking == null) return chunk;

    return VLLMChunk(
      id: chunk.id,
      created: chunk.created,
      model: chunk.model,
      systemFingerprint: chunk.systemFingerprint,
      vllmUsage: chunk.vllmUsage,
      choices: [
        VLLMChunkChoice(
          index: choice.index,
          delta: VLLMChunkChoiceDelta(
            role: choice.delta.role,
            content: split.content,
            thinking: _joinThinking(choice.delta.thinking, split.thinking),
            toolCalls: choice.delta.toolCalls,
          ),
          logProbs: choice.logProbs,
          finishReason: choice.finishReason,
        ),
        ...chunk.choices.skip(1),
      ],
    );
  }

  static String? _joinThinking(String? existing, String? parsed) {
    if (existing == null || existing.isEmpty) return parsed;
    if (parsed == null || parsed.isEmpty) return existing;
    return existing + parsed;
  }

  static VLLMChunk _toolCallChunk(
    VLLMChunk source,
    Map<int, VLLMToolCall> toolCallsByIndex,
  ) {
    return VLLMChunk(
      id: source.id,
      created: source.created,
      model: source.model,
      systemFingerprint: source.systemFingerprint,
      vllmUsage: source.vllmUsage,
      choices: [
        VLLMChunkChoice(
          index: 0,
          delta: VLLMChunkChoiceDelta(
            role: LLMRole.assistant.name,
            content: null,
            thinking: null,
            toolCalls: toolCallsByIndex.values.toList(growable: false),
          ),
          logProbs: null,
          finishReason: 'tool_calls',
        ),
      ],
    );
  }

  static int _recordMalformedEvent({
    required String event,
    required int malformedEventCount,
  }) {
    final updatedMalformedEventCount = malformedEventCount + 1;
    if (updatedMalformedEventCount >= _maxMalformedEvents) {
      final preview = _eventPreview(event);
      throw LLMApiException(
        'Failed to parse vLLM SSE stream after $_maxMalformedEvents malformed events. '
        'Last event preview: $preview',
      );
    }
    return updatedMalformedEventCount;
  }

  static String _eventPreview(String event, {int maxLength = 160}) {
    if (event.length <= maxLength) return event;
    return '${event.substring(0, maxLength)}...';
  }
}

class _ThinkingTagSplitter {
  static const _startTag = '<think>';
  static const _endTag = '</think>';

  bool _insideThinking = false;
  String _carry = '';

  /// Whether the splitter is currently inside a `<think>` block, which
  /// decides where a flushed carry belongs.
  bool get insideThinking => _insideThinking;

  /// Returns and clears text held back as a potential partial tag.
  ///
  /// A stream can end while the splitter is holding e.g. `<thin`, waiting to
  /// see whether it completes into a tag. At end of stream it never will, so
  /// the carry is real output and must be emitted rather than dropped.
  String flush() {
    final carried = _carry;
    _carry = '';
    return carried;
  }

  _ThinkingSplit split(String content) {
    final input = _carry + content;
    _carry = '';

    final visible = StringBuffer();
    final thinking = StringBuffer();
    var index = 0;

    while (index < input.length) {
      final tag = _insideThinking ? _endTag : _startTag;
      final tagIndex = input.indexOf(tag, index);
      if (tagIndex >= 0) {
        final text = input.substring(index, tagIndex);
        if (_insideThinking) {
          thinking.write(text);
        } else {
          visible.write(text);
        }
        _insideThinking = !_insideThinking;
        index = tagIndex + tag.length;
        continue;
      }

      final remainder = input.substring(index);
      final carryLength = _partialTagLength(remainder, tag);
      final emitLength = remainder.length - carryLength;
      if (emitLength > 0) {
        final text = remainder.substring(0, emitLength);
        if (_insideThinking) {
          thinking.write(text);
        } else {
          visible.write(text);
        }
      }
      if (carryLength > 0) {
        _carry = remainder.substring(emitLength);
      }
      break;
    }

    final visibleText = visible.toString();
    final thinkingText = thinking.toString();
    return _ThinkingSplit(
      content: visibleText.isEmpty ? null : visibleText,
      thinking: thinkingText.isEmpty ? null : thinkingText,
    );
  }

  int _partialTagLength(String text, String tag) {
    final maxLength = text.length < tag.length - 1
        ? text.length
        : tag.length - 1;
    for (var length = maxLength; length > 0; length--) {
      if (tag.startsWith(text.substring(text.length - length))) {
        return length;
      }
    }
    return 0;
  }
}

class _ThinkingSplit {
  const _ThinkingSplit({required this.content, required this.thinking});

  final String? content;
  final String? thinking;
}
