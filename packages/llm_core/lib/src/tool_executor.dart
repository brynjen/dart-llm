import 'dart:async';

import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_chunk.dart';
import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/llm_response.dart';
import 'package:llm_core/src/tool/llm_invalid_tool_call.dart';
import 'package:llm_core/src/tool/llm_tool.dart';
import 'package:llm_core/src/tool/llm_tool_call.dart';
import 'package:llm_core/src/tool/llm_tool_result.dart';

/// Executes tools from LLM chunks and manages the tool execution loop.
///
/// This class handles:
/// - Collecting tool calls from a stream of chunks
/// - Executing tools using the LLMTool interface
/// - Building tool response messages
/// - Managing tool attempt limits
/// - Recursively continuing conversations when tools are executed
class StreamToolExecutor {
  /// Creates a stream tool executor.
  StreamToolExecutor({
    required this.tools,
    required this.extra,
    required this.maxToolAttempts,
    required this.streamChatCallback,
  });

  /// The tools available for execution.
  final List<LLMTool> tools;

  /// Extra context to pass to tool executions.
  final dynamic extra;

  /// Maximum number of tool execution attempts.
  final int maxToolAttempts;

  /// Callback function to recursively call streamChat when tools need execution.
  ///
  /// Parameters: (model, messages, tools, extra, toolAttempts)
  final Stream<LLMChunk> Function(
    String model,
    List<LLMMessage> messages,
    List<LLMTool> tools,
    dynamic extra,
    int toolAttempts,
  )
  streamChatCallback;

  /// Processes a stream of chunks and executes tools when needed.
  ///
  /// [chunkStream] - Stream of LLM chunks
  /// [model] - The model identifier
  /// [initialMessages] - Initial conversation messages
  /// [toolAttempts] - Remaining tool attempts
  ///
  /// Returns a new stream that includes tool execution results.
  Stream<LLMChunk> executeTools({
    required Stream<LLMChunk> chunkStream,
    required String model,
    required List<LLMMessage> initialMessages,
    required int toolAttempts,
  }) async* {
    if (tools.isEmpty) {
      // No tools, just pass through the stream.
      yield* chunkStream;
      return;
    }

    final List<LLMMessage> workingMessages = List.from(initialMessages);
    final List<LLMToolCall> collectedToolCalls = [];
    final List<LLMInvalidToolCall> collectedInvalidToolCalls = [];
    LLMFinishReason? finishReason;
    var accumulatedContent = '';
    var accumulatedThinking = '';
    var sawDoneChunk = false;
    var sawFinalAssistantResponse = false;
    var sawToolCallsInRound = false;
    final loopPreviouslyStarted = initialMessages.any(
      (message) => message.role == LLMRole.tool,
    );

    await for (final chunk in chunkStream) {
      yield chunk;
      final message = chunk.message;

      // Accumulate content from chunks for the assistant message
      if (message?.role == LLMRole.assistant && message?.content != null) {
        accumulatedContent += message!.content!;
      }
      // Reasoning is accumulated the same way and for the same reason: without
      // it, a turn that called a tool lost everything the model thought before
      // deciding to call it, since only `content` survived into history.
      // `LLMMessage.thinking` is never serialized, so this cannot reach a
      // provider — it is for the caller's transcript.
      if (message?.role == LLMRole.assistant && message?.thinking != null) {
        accumulatedThinking += message!.thinking!;
      }

      // Collect tool calls from chunks
      if (message?.toolCalls != null && message!.toolCalls!.isNotEmpty) {
        sawToolCallsInRound = true;
        collectedToolCalls.addAll(message.toolCalls!);
      }
      // Invalid calls are part of the round too: the model asked for them and
      // is owed a tool result, even though they are never executed.
      if (message?.invalidToolCalls != null &&
          message!.invalidToolCalls!.isNotEmpty) {
        sawToolCallsInRound = true;
        collectedInvalidToolCalls.addAll(message.invalidToolCalls!);
      }
      finishReason = chunk.finishReason ?? finishReason;

      final hasCalls =
          collectedToolCalls.isNotEmpty || collectedInvalidToolCalls.isNotEmpty;

      if ((chunk.done ?? false)) {
        sawDoneChunk = true;
        if (message?.role == LLMRole.assistant && !hasCalls) {
          sawFinalAssistantResponse = true;
        }
      }

      // When the stream is done and we have tool calls, execute them.
      if ((chunk.done ?? false) && hasCalls) {
        // If attempts are exhausted, fail explicitly.
        if (toolAttempts <= 0) {
          throw ToolLoopIncompleteException(
            reason: 'Tool attempts exhausted before final assistant answer',
            attemptsUsed: _attemptsUsed(toolAttempts),
            attemptsRemaining: toolAttempts,
            lastRoundEndedWithDone: true,
            lastRoundHadToolCalls: true,
            hadFinalAssistantResponse: false,
          );
        }

        // Add assistant message with tool_calls (required for API compliance)
        workingMessages.add(
          LLMMessage(
            role: LLMRole.assistant,
            content: accumulatedContent.isEmpty ? null : accumulatedContent,
            thinking: accumulatedThinking.isEmpty ? null : accumulatedThinking,
            toolCalls: [
              for (final tc in collectedToolCalls) tc.toApiFormat(),
              for (final tc in collectedInvalidToolCalls) tc.toApiFormat(),
            ],
          ),
        );

        // Execute all collected tools
        var toolCallIndex = 0;
        for (final toolCall in collectedToolCalls) {
          final tool = tools.firstWhere(
            (t) => t.name == toolCall.name,
            orElse: () => throw Exception('Tool ${toolCall.name} not found'),
          );

          LLMToolResult result;
          try {
            result = LLMToolResult.from(
              await tool.execute(toolCall.argumentsJson, extra: extra),
              toolName: toolCall.name,
            );
          } catch (e) {
            // If a tool throws, capture the error as a tool message instead of
            // crashing the whole stream. This allows callers to handle tool
            // failures gracefully.
            //
            // The text is unchanged from before `LLMToolResult` existed, both
            // for callers matching on it and because `ClaudeMessageConverter`
            // still falls back to matching it for messages this executor did
            // not build.
            result = LLMToolResult.failure(
              'Tool ${toolCall.name} failed: $e',
              metadata: {'exception': e.toString()},
            );
          }

          // Ensure we always have a non-empty toolCallId, even if the backend
          // did not provide an id for the tool call.
          final effectiveToolCallId =
              (toolCall.id != null && toolCall.id!.isNotEmpty)
              ? toolCall.id!
              : 'tool_${toolCallIndex}_${toolCall.name}';

          final toolResponseStr = result.content;

          // Emit tool result chunk so the chat can display it
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
              toolName: toolCall.name,
              toolResult: result,
            ),
            status: toolCall.name,
            done: false,
          );

          workingMessages.add(
            LLMMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
              // `status` predates `toolName` and is still set so a history
              // serialized by an older consumer keeps naming its tools.
              status: toolCall.name,
              toolName: toolCall.name,
              toolResult: result,
            ),
          );

          toolCallIndex++;
        }

        // Invalid calls are never executed — following LangChain and the
        // Vercel AI SDK. The model gets the parse error as the tool result so
        // it can re-issue the call, and when the turn was cut off by the token
        // limit it is told so, since re-issuing the same call unchanged would
        // be cut off again.
        for (final invalidCall in collectedInvalidToolCalls) {
          final effectiveToolCallId =
              (invalidCall.id != null && invalidCall.id!.isNotEmpty)
              ? invalidCall.id!
              : 'tool_${toolCallIndex}_${invalidCall.name}';
          final toolResponseStr = finishReason == LLMFinishReason.length
              ? 'Tool ${invalidCall.name} was not called: the response hit '
                    'the output token limit before the arguments were '
                    'complete. Produce a shorter call, for example by '
                    'splitting the work across several calls.'
              : 'Tool ${invalidCall.name} was not called: its arguments are '
                    'not valid JSON (${invalidCall.error}).';

          // An invalid call is a failure, and saying so in the text alone was
          // not enough: `ClaudeMessageConverter` detected failures by matching
          // 'Tool <name> failed:', which this wording does not match, so a
          // parse error reached Anthropic without `is_error` and the model read
          // the error message as data.
          final result = LLMToolResult.failure(
            toolResponseStr,
            metadata: {
              'invalid_arguments': invalidCall.arguments,
              'parse_error': invalidCall.error,
              if (finishReason != null) 'finish_reason': finishReason.name,
            },
          );

          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
              toolName: invalidCall.name,
              toolResult: result,
            ),
            status: invalidCall.name,
            done: false,
          );

          workingMessages.add(
            LLMMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
              status: invalidCall.name,
              toolName: invalidCall.name,
              toolResult: result,
            ),
          );

          toolCallIndex++;
        }

        // Continue the conversation with tool results if we have attempts left
        if (toolAttempts > 0) {
          // Each recursion builds a fresh executor whose budget is already
          // decremented, so the level that finally runs out has no idea how
          // many rounds preceded it and reports `attemptsUsed: 0`. This level
          // does know its own budget, so it restates the accounting on the way
          // out; the outermost frame has the true ceiling and wins.
          //
          // The rewrite has to happen on the stream rather than in a
          // `try` around the `yield*`: an error from a yielded stream goes
          // straight to the subscriber without unwinding through this
          // generator, so an enclosing catch never sees it.
          yield* streamChatCallback(
            model,
            workingMessages,
            tools,
            extra,
            toolAttempts - 1,
          ).handleError((Object error) {
            final e = error as ToolLoopIncompleteException;
            throw ToolLoopIncompleteException(
              reason: e.reason,
              attemptsUsed: _attemptsUsed(e.attemptsRemaining),
              attemptsRemaining: e.attemptsRemaining,
              lastRoundEndedWithDone: e.lastRoundEndedWithDone,
              lastRoundHadToolCalls: e.lastRoundHadToolCalls,
              hadFinalAssistantResponse: e.hadFinalAssistantResponse,
            );
          }, test: (error) => error is ToolLoopIncompleteException);
          return;
        }
      }
    }

    final toolLoopStarted = loopPreviouslyStarted || sawToolCallsInRound;
    if (toolLoopStarted && !sawFinalAssistantResponse) {
      throw ToolLoopIncompleteException(
        reason: sawDoneChunk
            ? 'Stream ended without a final assistant answer'
            : 'Stream terminated before completion',
        attemptsUsed: _attemptsUsed(toolAttempts),
        attemptsRemaining: toolAttempts,
        lastRoundEndedWithDone: sawDoneChunk,
        lastRoundHadToolCalls: sawToolCallsInRound,
        hadFinalAssistantResponse: sawFinalAssistantResponse,
      );
    }
  }

  int _attemptsUsed(int attemptsRemaining) {
    final used = maxToolAttempts - attemptsRemaining;
    return used < 0 ? 0 : used;
  }
}
