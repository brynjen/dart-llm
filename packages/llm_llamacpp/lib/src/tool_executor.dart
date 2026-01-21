import 'dart:convert';

import 'package:llm_core/llm_core.dart' show
    LLMLogger,
    LLMMessage,
    LLMRole,
    LLMTool,
    LLMToolCall;

/// Executes tool calls and returns tool response messages.
///
/// This class handles the execution of tool calls, including tool lookup,
/// argument parsing, execution, error handling, and response formatting.
class ToolExecutor {
  /// Executes a list of tool calls and returns the corresponding tool messages.
  ///
  /// [toolCalls] - List of tool calls to execute.
  /// [tools] - Available tools that can be executed.
  /// [extra] - Additional context to pass to tool executions.
  /// [logger] - Logger for logging tool execution details.
  ///
  /// Returns a list of [LLMMessage] objects with role [LLMRole.tool]
  /// containing the tool execution results.
  static Future<List<LLMMessage>> executeTools(
    List<LLMToolCall> toolCalls,
    List<LLMTool> tools,
    dynamic extra,
    LLMLogger logger,
  ) async {
    final workingMessages = <LLMMessage>[];

    // Execute tools and add responses
    for (final toolCall in toolCalls) {
      logger.fine('Executing tool: ${toolCall.name}');
      final tool = tools.firstWhere(
        (t) => t.name == toolCall.name,
        orElse: () {
          logger.severe('Tool ${toolCall.name} not found!');
          throw Exception('Tool ${toolCall.name} not found');
        },
      );

      try {
        final args = json.decode(toolCall.arguments);
        logger.fine('Tool args: $args');
        final toolResponse =
            await tool.execute(args, extra: extra) ??
            'Tool ${toolCall.name} returned null';
        logger.fine('Tool response: $toolResponse');

        workingMessages.add(
          LLMMessage(
            role: LLMRole.tool,
            content: toolResponse.toString(),
            toolCallId: toolCall.id,
          ),
        );
      } catch (e) {
        logger.warning('Tool execution error: $e');
        workingMessages.add(
          LLMMessage(
            role: LLMRole.tool,
            content: 'Error executing tool: $e',
            toolCallId: toolCall.id,
          ),
        );
      }
    }

    return workingMessages;
  }
}
