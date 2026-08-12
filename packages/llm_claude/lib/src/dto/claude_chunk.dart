import 'package:llm_core/llm_core.dart';

/// Represents a streamed chunk from the Claude SSE stream.
class ClaudeChunk extends LLMChunk {
  ClaudeChunk({
    super.model,
    super.done,
    super.createdAt,
    super.message,
    super.promptEvalCount,
    super.evalCount,
    super.usage,
    super.finishReason,
    super.providerMetadata,
    super.status,
  });
}

/// Represents a tool use block accumulated during streaming.
class ClaudeToolUseBlock {
  ClaudeToolUseBlock({
    required this.id,
    required this.name,
    this.inputJson = '',
  });

  final String id;
  final String name;
  String inputJson;
}
