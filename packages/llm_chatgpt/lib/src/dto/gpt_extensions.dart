import 'package:llm_chatgpt/src/dto/gpt_choice.dart';
import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';
import 'package:llm_core/llm_core.dart';

/// Extension to convert GPT tool calls to LLM tool calls.
extension GPTToolCallToLLMToolCallExt on List<GPTToolCall> {
  List<LLMToolCall> get toLLMToolCalls {
    List<GPTToolCall> onlyFirst = [];
    if (isNotEmpty) {
      onlyFirst = [first];
    }
    return onlyFirst
        .map(
          (call) => LLMToolCall(
            id: call.id,
            name: call.function.name!,
            arguments: call.function.arguments,
          ),
        )
        .toList(growable: false);
  }
}

/// Extension to convert GPT message to LLM message.
extension GPTMessageToLLMMessageExt on GPTMessage {
  LLMMessage get toLLMMessage {
    List<GPTToolCall>? firstToolCall;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      firstToolCall = [toolCalls!.first];
    }
    return LLMMessage(
      content: content,
      role: LLMRole.values.firstWhere((e) => e.name == role),
      toolCalls: firstToolCall?.map((e) => e.toJson()).toList(growable: false),
    );
  }
}
