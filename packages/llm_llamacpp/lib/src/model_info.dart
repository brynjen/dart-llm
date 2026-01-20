import 'package:llm_llamacpp/src/gguf_metadata.dart';
import 'package:llm_llamacpp/src/model_converter.dart';

// ============================================================
// Model Acquisition Progress
// ============================================================

/// Stages of model acquisition.
enum ModelAcquisitionStage {
  /// Checking what files are available
  checking,

  /// Downloading GGUF file
  downloading,

  /// Converting safetensors to GGUF
  converting,

  /// Quantizing the model
  quantizing,

  /// Acquisition complete
  complete,

  /// Acquisition failed
  failed,
}

/// Progress status for model acquisition.
class ModelAcquisitionStatus {
  ModelAcquisitionStatus({
    required this.stage,
    required this.message,
    this.progress,
    this.modelPath,
    this.error,
  });

  /// Current acquisition stage.
  final ModelAcquisitionStage stage;

  /// Status message.
  final String message;

  /// Progress (0.0 to 1.0) if available.
  final double? progress;

  /// Path to the acquired model (set when complete).
  final String? modelPath;

  /// Error message if failed.
  final String? error;

  /// Whether acquisition is complete.
  bool get isComplete => stage == ModelAcquisitionStage.complete;

  /// Whether acquisition failed.
  bool get isError => stage == ModelAcquisitionStage.failed;

  /// Progress as percentage string.
  String get progressPercent =>
      progress != null ? '${(progress! * 100).toStringAsFixed(1)}%' : '';
}

/// Information about a discovered GGUF model.
class ModelInfo {
  ModelInfo({
    required this.path,
    required this.name,
    required this.fileSize,
    this.metadata,
    this.isLoaded = false,
  });

  /// Full path to the GGUF file.
  final String path;

  /// Model name (derived from filename).
  final String name;

  /// File size in bytes.
  final int fileSize;

  /// GGUF metadata (if read).
  final GgufMetadata? metadata;

  /// Whether this model is currently loaded.
  final bool isLoaded;

  /// Get human-readable file size.
  String get fileSizeLabel {
    if (fileSize >= 1024 * 1024 * 1024) {
      return '${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (fileSize >= 1024 * 1024) {
      return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    }
  }

  @override
  String toString() {
    final meta = metadata;
    if (meta != null) {
      return 'ModelInfo($name, ${meta.architecture ?? "unknown"}, '
          '${meta.sizeLabel}, ${meta.quantizationType ?? "?"}, $fileSizeLabel)';
    }
    return 'ModelInfo($name, $fileSizeLabel)';
  }
}

/// Progress information for model downloads.
class DownloadProgress {
  DownloadProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    this.status,
  });

  /// Total size in bytes.
  final int totalBytes;

  /// Downloaded bytes so far.
  final int downloadedBytes;

  /// Status message.
  final String? status;

  /// Progress as a fraction (0.0 to 1.0).
  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  /// Progress as a percentage string.
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';

  /// Whether the download is complete.
  bool get isComplete => downloadedBytes >= totalBytes && totalBytes > 0;
}

/// How to acquire a model.
enum AcquisitionMethod {
  /// Model has GGUF files available for direct download.
  directDownload,

  /// Model only has safetensors, needs conversion.
  convertFromSafetensors,

  /// Model not available in a usable format.
  notAvailable,
}

/// Plan for acquiring a model from HuggingFace.
class ModelAcquisitionPlan {
  ModelAcquisitionPlan({
    required this.method,
    required this.repoId,
    this.filename,
    this.availableGgufFiles,
    this.suggestedQuantization,
    this.error,
  });

  /// How to acquire the model.
  final AcquisitionMethod method;

  /// HuggingFace repository ID.
  final String repoId;

  /// Recommended filename for direct download.
  final String? filename;

  /// Available GGUF files (for direct download).
  final List<String>? availableGgufFiles;

  /// Suggested quantization (for conversion).
  final QuantizationType? suggestedQuantization;

  /// Error message (for notAvailable).
  final String? error;

  @override
  String toString() {
    switch (method) {
      case AcquisitionMethod.directDownload:
        return 'Download GGUF: $filename (${availableGgufFiles?.length ?? 0} available)';
      case AcquisitionMethod.convertFromSafetensors:
        return 'Convert safetensors → GGUF (suggested: ${suggestedQuantization?.displayName})';
      case AcquisitionMethod.notAvailable:
        return 'Not available: $error';
    }
  }
}
