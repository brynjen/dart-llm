/// Usage metadata from the Gemini API response.
class GeminiUsage {
  const GeminiUsage({
    required this.promptTokenCount,
    required this.candidatesTokenCount,
  });

  factory GeminiUsage.fromJson(Map<String, dynamic> json) {
    return GeminiUsage(
      promptTokenCount: (json['promptTokenCount'] as num?)?.toInt() ?? 0,
      candidatesTokenCount:
          (json['candidatesTokenCount'] as num?)?.toInt() ?? 0,
    );
  }

  final int promptTokenCount;
  final int candidatesTokenCount;
}
