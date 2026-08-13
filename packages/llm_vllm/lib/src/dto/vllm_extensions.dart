import 'package:llm_vllm/src/dto/vllm_tool_call.dart';
import 'package:llm_core/llm_core.dart';

/// Extension to convert VLLM tool calls to LLM tool calls.
extension VLLMToolCallToLLMToolCallExt on List<VLLMToolCall> {
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
