/// Represents a locally available Ollama model.
class OllamaModel {
  final String name;
  final String model;
  final DateTime modifiedAt;
  final int size;
  final String digest;
  final OllamaModelDetails details;

  OllamaModel({
    required this.name,
    required this.model,
    required this.modifiedAt,
    required this.size,
    required this.digest,
    required this.details,
  });

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    return OllamaModel(
      name: json['name'],
      model: json['model'],
      modifiedAt: DateTime.parse(json['modified_at']),
      size: json['size'],
      digest: json['digest'],
      details: OllamaModelDetails.fromJson(json['details']),
    );
  }

  @override
  String toString() {
    return 'OllamaModel(name: $name, size: $size, modifiedAt: $modifiedAt)';
  }
}

/// Details about an Ollama model.
class OllamaModelDetails {
  final String parentModel;
  final String format;
  final String family;
  final List<String> families;
  final String parameterSize;
  final String quantizationLevel;

  OllamaModelDetails({
    required this.parentModel,
    required this.format,
    required this.family,
    required this.families,
    required this.parameterSize,
    required this.quantizationLevel,
  });

  factory OllamaModelDetails.fromJson(Map<String, dynamic> json) {
    return OllamaModelDetails(
      parentModel: json['parent_model'] ?? '',
      format: json['format'],
      family: json['family'],
      families: List<String>.from(json['families'] ?? []),
      parameterSize: json['parameter_size'],
      quantizationLevel: json['quantization_level'],
    );
  }
}

/// Extended information about an Ollama model.
class OllamaModelInfo {
  final String modelfile;
  final String parameters;
  final String template;
  final OllamaModelDetails details;
  final Map<String, dynamic>? modelInfo;

  OllamaModelInfo({
    required this.modelfile,
    required this.parameters,
    required this.template,
    required this.details,
    this.modelInfo,
  });

  factory OllamaModelInfo.fromJson(Map<String, dynamic> json) {
    return OllamaModelInfo(
      modelfile: json['modelfile'] ?? '',
      parameters: json['parameters'] ?? '',
      template: json['template'] ?? '',
      details: OllamaModelDetails.fromJson(json['details']),
      modelInfo: json['model_info'],
    );
  }

  @override
  String toString() {
    return 'OllamaModelInfo(details: $details)';
  }
}

/// Ollama server version information.
class OllamaVersion {
  final String version;

  OllamaVersion({required this.version});

  factory OllamaVersion.fromJson(Map<String, dynamic> json) {
    return OllamaVersion(version: json['version']);
  }

  @override
  String toString() {
    return 'OllamaVersion(version: $version)';
  }
}

/// Progress information for model pull operations.
class OllamaPullProgress {
  final String status;
  final String? digest;
  final int? total;
  final int? completed;

  OllamaPullProgress({
    required this.status,
    this.digest,
    this.total,
    this.completed,
  });

  factory OllamaPullProgress.fromJson(Map<String, dynamic> json) {
    return OllamaPullProgress(
      status: json['status'],
      digest: json['digest'],
      total: json['total'],
      completed: json['completed'],
    );
  }

  /// Progress as a value between 0.0 and 1.0.
  double get progress {
    if (total == null || completed == null || total == 0) return 0.0;
    return completed! / total!;
  }

  @override
  String toString() {
    return 'OllamaPullProgress(status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}

