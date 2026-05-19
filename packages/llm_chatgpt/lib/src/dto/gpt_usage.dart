/// Token usage details.
class GPTUsageTokenDetails {
  GPTUsageTokenDetails({required this.cachedTokens});

  final int cachedTokens;

  factory GPTUsageTokenDetails.fromJson(Map<String, dynamic> json) =>
      GPTUsageTokenDetails(cachedTokens: json['cached_tokens']);

  Map<String, dynamic> toJson() => {'cached_tokens': cachedTokens};
}

/// Token usage statistics.
class GPTUsage {
  GPTUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.usageTokenDetails,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final GPTUsageTokenDetails? usageTokenDetails;

  factory GPTUsage.fromJson(Map<String, dynamic> json) => GPTUsage(
    promptTokens: json['prompt_tokens'],
    completionTokens: json['completion_tokens'],
    totalTokens: json['total_tokens'],
    usageTokenDetails: json['prompt_tokens_details'] != null
        ? GPTUsageTokenDetails.fromJson(json['prompt_tokens_details'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
    'prompt_tokens_details': usageTokenDetails?.toJson(),
  };
}
