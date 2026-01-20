/// Exception thrown when trying to use thinking on a model that doesn't support it.
class ThinkingNotSupportedException implements Exception {
  const ThinkingNotSupportedException(this.model, this.message);

  /// The error message.
  final String message;

  /// The model that doesn't support thinking.
  final String model;

  @override
  String toString() => 'ThinkingNotSupportedException: $message';
}

/// Exception thrown when trying to use tools on a model that doesn't support them.
class ToolsNotSupportedException implements Exception {
  const ToolsNotSupportedException(this.model, this.message);

  /// The error message.
  final String message;

  /// The model that doesn't support tools.
  final String model;

  @override
  String toString() => 'ToolsNotSupportedException: $message';
}

/// Exception thrown when trying to use images/vision on a model that doesn't support it.
class VisionNotSupportedException implements Exception {
  const VisionNotSupportedException(this.model, this.message);

  /// The error message.
  final String message;

  /// The model that doesn't support vision.
  final String model;

  @override
  String toString() => 'VisionNotSupportedException: $message';
}

/// Exception thrown when an LLM API request fails.
class LLMApiException implements Exception {
  const LLMApiException(this.message, {this.statusCode, this.responseBody});

  /// The error message.
  final String message;

  /// The HTTP status code (if applicable).
  final int? statusCode;

  /// The raw response body (if available).
  final String? responseBody;

  @override
  String toString() {
    if (statusCode != null) {
      return 'LLMApiException: HTTP $statusCode - $message';
    }
    return 'LLMApiException: $message';
  }
}

/// Exception thrown when model loading fails.
class ModelLoadException implements Exception {
  const ModelLoadException(this.message, {this.modelPath});

  /// The error message.
  final String message;

  /// The model that failed to load.
  final String? modelPath;

  @override
  String toString() => 'ModelLoadException: $message';
}

// Backwards compatibility aliases
@Deprecated('Use ThinkingNotSupportedException instead')
typedef ThinkingNotAllowed = ThinkingNotSupportedException;

@Deprecated('Use ToolsNotSupportedException instead')
typedef ToolsNotAllowed = ToolsNotSupportedException;

@Deprecated('Use VisionNotSupportedException instead')
typedef VisionNotAllowed = VisionNotSupportedException;
