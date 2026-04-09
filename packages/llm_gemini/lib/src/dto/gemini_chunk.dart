import 'package:llm_core/llm_core.dart';

/// Represents a streamed chunk from the Gemini SSE stream.
class GeminiChunk extends LLMChunk {
  GeminiChunk({
    super.model,
    super.done,
    super.createdAt,
    super.message,
    super.promptEvalCount,
    super.evalCount,
    super.status,
  });
}
