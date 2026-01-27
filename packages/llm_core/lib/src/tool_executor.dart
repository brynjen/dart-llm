import 'dart:async';
import 'dart:convert';

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
    if (tools.isEmpty || toolAttempts <= 0) {
      // No tools or no attempts left, just pass through the stream
      yield* chunkStream;
      return;
    }

    final List<LLMMessage> workingMessages = List.from(initialMessages);
    final List<LLMToolCall> collectedToolCalls = [];

    await for (final chunk in chunkStream) {
      yield chunk;

      // Collect tool calls from chunks
      if (chunk.message?.toolCalls != null &&
          chunk.message!.toolCalls!.isNotEmpty) {
        collectedToolCalls.addAll(chunk.message!.toolCalls!);
      }

      // When the stream is done and we have tool calls, execute them
      if ((chunk.done ?? false) && collectedToolCalls.isNotEmpty) {
        // Execute all collected tools
        for (final toolCall in collectedToolCalls) {
          final tool = tools.firstWhere(
            (t) => t.name == toolCall.name,
            orElse: () => throw Exception('Tool ${toolCall.name} not found'),
          );

          final toolResponse =
              await tool.execute(
                json.decode(toolCall.arguments),
                extra: extra,
              ) ??
              'Tool ${toolCall.name} returned null';

          workingMessages.add(
            LLMMessage(
              content: toolResponse is String
                  ? toolResponse
                  : toolResponse.toString(),
              role: LLMRole.tool,
              toolCallId: toolCall.id,
            ),
          );
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
  }
}
