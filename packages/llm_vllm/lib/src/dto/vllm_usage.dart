/// Token usage details.
class VLLMUsageTokenDetails {
  VLLMUsageTokenDetails({required this.cachedTokens});

  final int cachedTokens;

  factory VLLMUsageTokenDetails.fromJson(Map<String, dynamic> json) =>
      VLLMUsageTokenDetails(cachedTokens: json['cached_tokens'] as int? ?? 0);

  Map<String, dynamic> toJson() => {'cached_tokens': cachedTokens};
}

/// Token usage statistics.
class VLLMUsage {
  VLLMUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.usageTokenDetails,
    this.reasoningTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final VLLMUsageTokenDetails? usageTokenDetails;

  /// Reasoning tokens from `completion_tokens_details`, when reported.
  final int? reasoningTokens;

  factory VLLMUsage.fromJson(Map<String, dynamic> json) => VLLMUsage(
    promptTokens: json['prompt_tokens'] as int? ?? 0,
    completionTokens: json['completion_tokens'] as int? ?? 0,
    totalTokens:
        json['total_tokens'] as int? ??
        (json['prompt_tokens'] as int? ?? 0) +
            (json['completion_tokens'] as int? ?? 0),
    usageTokenDetails: json['prompt_tokens_details'] != null
        ? VLLMUsageTokenDetails.fromJson(
            json['prompt_tokens_details'] as Map<String, dynamic>,
          )
        : null,
    reasoningTokens:
        (json['completion_tokens_details']
                as Map<String, dynamic>?)?['reasoning_tokens']
            as int?,
  );

  Map<String, dynamic> toJson() => {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
    'prompt_tokens_details': usageTokenDetails?.toJson(),
    if (reasoningTokens != null)
      'completion_tokens_details': {'reasoning_tokens': reasoningTokens},
  };
}
