/// Usage statistics from the Claude API response.
class ClaudeUsage {
  const ClaudeUsage({required this.inputTokens, required this.outputTokens});

  factory ClaudeUsage.fromJson(Map<String, dynamic> json) {
    return ClaudeUsage(
      inputTokens: (json['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  final int inputTokens;
  final int outputTokens;
}
