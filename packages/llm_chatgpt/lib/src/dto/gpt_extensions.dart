import 'package:llm_chatgpt/src/dto/gpt_choice.dart';
import 'package:llm_chatgpt/src/dto/gpt_tool_call.dart';
import 'package:llm_core/llm_core.dart';

/// Extension to convert GPT tool calls to LLM tool calls.
extension GPTToolCallToLLMToolCallExt on List<GPTToolCall> {
  /// Converts every tool call in the list.
  ///
  /// A model asked for parallel tool calls returns all of them in one message,
  /// and dropping any is silent data loss: the caller executes one tool and
  /// answers as though that were the whole request.
  List<LLMToolCall> get toLLMToolCalls {
    return asMap().entries
        .where((entry) => entry.value.function.name != null)
        .map((entry) {
          final index = entry.key;
          final call = entry.value;
          final rawId = call.id;
          final id = (rawId != null && rawId.isNotEmpty)
              ? rawId
              : 'tool_${index}_${call.function.name}';

          return LLMToolCall(
            id: id,
            name: call.function.name!,
            arguments: call.function.arguments,
          );
        })
        .toList(growable: false);
  }
}

/// Extension to convert GPT message to LLM message.
extension GPTMessageToLLMMessageExt on GPTMessage {
  /// Converts the message, preserving every tool call it carries.
  LLMMessage get toLLMMessage {
    return LLMMessage(
      content: content,
      role: LLMRole.values.firstWhere((e) => e.name == role),
      toolCalls: toolCalls?.map((e) => e.toJson()).toList(growable: false),
    );
  }
}

/// Extension to convert raw per-chunk tool call fragments to core deltas.
extension GPTToolCallToLLMToolCallDeltaExt on List<GPTToolCall> {
  /// Maps the fragments carried by a single stream event.
  ///
  /// Unlike [GPTToolCallToLLMToolCallExt.toLLMToolCalls] this keeps every
  /// entry and every index: continuation fragments carry no name and no id by
  /// design, and those are exactly what a delta exists to surface.
  List<LLMToolCallDelta> get toLLMToolCallDeltas => map((call) {
    final arguments = call.function.arguments;
    return LLMToolCallDelta(
      index: call.index,
      id: call.id,
      name: call.function.name,
      // OpenAI sends "" on the name fragment; an empty fragment is not a
      // fragment.
      argumentsDelta: arguments.isEmpty ? null : arguments,
    );
  }).toList(growable: false);
}
