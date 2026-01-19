import 'model_converter.dart';

// ============================================================
// Model Exceptions
// ============================================================

/// Thrown when a requested model file is not found in the repository.
class ModelNotFoundException implements Exception {
  ModelNotFoundException({
    required this.repoId,
    required this.message,
    this.availableFiles = const [],
  });

  /// The HuggingFace repository ID.
  final String repoId;

  /// Error message.
  final String message;

  /// List of available GGUF files in the repository.
  final List<String> availableFiles;

  @override
  String toString() {
    final buffer = StringBuffer('ModelNotFoundException: $message\n');
    buffer.writeln("Repository: '$repoId'");

    if (availableFiles.isNotEmpty) {
      buffer.writeln('\nAvailable GGUF files:');
      for (final file in availableFiles) {
        buffer.writeln('  - $file');
      }
      buffer.writeln(
        "\nSpecify file: getModel('$repoId', preferredFile: '${availableFiles.first}')",
      );
    }

    return buffer.toString();
  }
}

/// Thrown when multiple GGUF files match the requested criteria.
class AmbiguousModelException implements Exception {
  AmbiguousModelException({
    required this.repoId,
    required this.message,
    required this.matchingFiles,
  });

  /// The HuggingFace repository ID.
  final String repoId;

  /// Error message.
  final String message;

  /// List of files that matched the criteria.
  final List<String> matchingFiles;

  @override
  String toString() {
    final buffer = StringBuffer('AmbiguousModelException: $message\n');
    buffer.writeln("Repository: '$repoId'");
    buffer.writeln('\nMatching files:');
    for (final file in matchingFiles) {
      buffer.writeln('  - $file');
    }
    buffer.writeln(
      "\nSpecify file: getModel('$repoId', preferredFile: '${matchingFiles.first}')",
    );
    return buffer.toString();
  }
}

/// Thrown when a repository only has safetensors and quantization is required.
class ConversionRequiredException implements Exception {
  ConversionRequiredException({
    required this.repoId,
    required this.message,
  });

  /// The HuggingFace repository ID.
  final String repoId;

  /// Error message.
  final String message;

  @override
  String toString() {
    final buffer = StringBuffer('ConversionRequiredException: $message\n');
    buffer.writeln("Repository: '$repoId' only has safetensors (no GGUF).");
    buffer.writeln('Conversion requires a quantization parameter.\n');
    buffer.writeln(
      "Example: getModel('$repoId', quantization: QuantizationType.q4_k_m)",
    );
    buffer.writeln('\nAvailable quantizations:');
    for (final q in QuantizationType.values) {
      buffer.writeln('  - ${q.name} (${q.displayName})');
    }
    return buffer.toString();
  }
}

/// Thrown when a repository has no usable model files.
class UnsupportedModelException implements Exception {
  UnsupportedModelException({
    required this.repoId,
    required this.message,
  });

  /// The HuggingFace repository ID.
  final String repoId;

  /// Error message.
  final String message;

  @override
  String toString() {
    return "UnsupportedModelException: $message\nRepository: '$repoId'";
  }
}

// ============================================================
// LoRA Exceptions
// ============================================================

/// Thrown when a LoRA adapter fails to load.
class LoraLoadException implements Exception {
  LoraLoadException({
    required this.path,
    required this.message,
  });

  /// Path to the LoRA file that failed to load.
  final String path;

  /// Error message.
  final String message;

  @override
  String toString() {
    return "LoraLoadException: $message\nPath: '$path'";
  }
}
