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

/// Extension to convert raw per-chunk tool call fragments to core deltas.
extension VLLMToolCallToLLMToolCallDeltaExt on List<VLLMToolCall> {
  /// Maps the fragments carried by a single stream event.
  ///
  /// Unlike [VLLMToolCallToLLMToolCallExt.toLLMToolCalls] this keeps entries
  /// whose `function.name` is null: every continuation fragment is name-less,
  /// and those are exactly what a delta exists to surface. Ids are likewise
  /// left null rather than synthesized — only the first fragment for an index
  /// carries one, and inventing the rest would imply a correlation that the
  /// `index` already provides.
  List<LLMToolCallDelta> get toLLMToolCallDeltas => map((call) {
    final arguments = call.function.arguments;
    return LLMToolCallDelta(
      index: call.index,
      id: call.id,
      name: call.function.name,
      // vLLM omits `arguments` on the name fragment; OpenAI sends "". Both
      // mean "no argument text yet", and an empty fragment is not a fragment.
      argumentsDelta: arguments.isEmpty ? null : arguments,
    );
  }).toList(growable: false);
}
