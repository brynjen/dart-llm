import 'package:llm_core/llm_core.dart'
    show LLMLogger, LLMMessage, LLMRole, LLMTool, LLMToolCall, LLMToolResult;

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

      LLMToolResult result;
      try {
        final args = toolCall.argumentsJson;
        logger.fine('Tool args: $args');
        result = LLMToolResult.from(
          await tool.execute(args, extra: extra),
          toolName: toolCall.name,
        );
        logger.fine('Tool response: ${result.content}');
      } catch (e) {
        logger.warning('Tool execution error: $e');
        // Was `'Error executing tool: $e'`, which no other backend produced.
        // `ClaudeMessageConverter` detects a failed tool by matching the
        // wording `llm_core` uses, so a history built here and replayed against
        // Anthropic lost its error flag. Same text as `StreamToolExecutor` now.
        result = LLMToolResult.failure(
          'Tool ${toolCall.name} failed: $e',
          metadata: {'exception': e.toString()},
        );
      }

      workingMessages.add(
        LLMMessage(
          role: LLMRole.tool,
          content: result.content,
          toolCallId: toolCall.id,
          // This path set no tool name at all, so a history it produced left
          // Gemini's `function_result.name` empty.
          status: toolCall.name,
          toolName: toolCall.name,
          toolResult: result,
        ),
      );
    }

    return workingMessages;
  }
}
