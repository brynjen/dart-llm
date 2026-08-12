/// Capabilities advertised by a repository/model combination.
class LLMCapabilities {
  /// Creates a capability descriptor.
  const LLMCapabilities({
    this.streaming = true,
    this.tools = false,
    this.vision = false,
    this.structuredOutput = false,
    this.thinking = false,
    this.embeddings = false,
  });

  /// Whether streaming chat is supported.
  final bool streaming;

  /// Whether function/tool calling is supported.
  final bool tools;

  /// Whether image or multimodal input is supported.
  final bool vision;

  /// Whether structured JSON/schema output is supported.
  final bool structuredOutput;

  /// Whether separate thinking/reasoning output is supported.
  final bool thinking;

  /// Whether embeddings are supported.
  final bool embeddings;
}
