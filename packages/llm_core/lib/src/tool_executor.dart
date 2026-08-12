import 'dart:async';
import 'dart:convert';

import 'package:llm_core/src/exceptions.dart';
import 'package:llm_core/src/llm_chunk.dart';
import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/tool/llm_tool.dart';
import 'package:llm_core/src/tool/llm_tool_call.dart';

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
    var accumulatedContent = '';
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

      // Collect tool calls from chunks
      if (message?.toolCalls != null && message!.toolCalls!.isNotEmpty) {
        sawToolCallsInRound = true;
        collectedToolCalls.addAll(message.toolCalls!);
      }

      if ((chunk.done ?? false)) {
        sawDoneChunk = true;
        if (message?.role == LLMRole.assistant && collectedToolCalls.isEmpty) {
          sawFinalAssistantResponse = true;
        }
      }

      // When the stream is done and we have tool calls, execute them.
      if ((chunk.done ?? false) && collectedToolCalls.isNotEmpty) {
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
            toolCalls: collectedToolCalls
                .map((tc) => tc.toApiFormat())
                .toList(growable: false),
          ),
        );

        // Execute all collected tools
        var toolCallIndex = 0;
        for (final toolCall in collectedToolCalls) {
          final tool = tools.firstWhere(
            (t) => t.name == toolCall.name,
            orElse: () => throw Exception('Tool ${toolCall.name} not found'),
          );

          dynamic toolResponse;
          try {
            toolResponse =
                await tool.execute(
                  json.decode(toolCall.arguments),
                  extra: extra,
                ) ??
                'Tool ${toolCall.name} returned null';
          } catch (e) {
            // If a tool throws, capture the error as a tool message instead of
            // crashing the whole stream. This allows callers to handle tool
            // failures gracefully.
            toolResponse = 'Tool ${toolCall.name} failed: $e';
          }

          // Ensure we always have a non-empty toolCallId, even if the backend
          // did not provide an id for the tool call.
          final effectiveToolCallId =
              (toolCall.id != null && toolCall.id!.isNotEmpty)
              ? toolCall.id!
              : 'tool_${toolCallIndex}_${toolCall.name}';

          final toolResponseStr = toolResponse is String
              ? toolResponse
              : toolResponse.toString();

          // Emit tool result chunk so the chat can display it
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
            ),
            status: toolCall.name,
            done: false,
          );

          workingMessages.add(
            LLMMessage(
              content: toolResponseStr,
              role: LLMRole.tool,
              toolCallId: effectiveToolCallId,
              status: toolCall.name,
            ),
          );

          toolCallIndex++;
        }

        // Continue the conversation with tool results if we have attempts left
        if (toolAttempts > 0) {
          yield* streamChatCallback(
            model,
            workingMessages,
            tools,
            extra,
            toolAttempts - 1,
          );
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
