import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bindings/llama_bindings.dart';
import 'gguf_metadata.dart';
import 'llamacpp_model.dart';
import 'loader/loader.dart';
import 'model_converter.dart';

// ============================================================
// Exceptions
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
        "\nSpecify file: getModel('$repoId', preferredFile: '${availableFiles.first}')"
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
      "\nSpecify file: getModel('$repoId', preferredFile: '${matchingFiles.first}')"
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
      "Example: getModel('$repoId', quantization: QuantizationType.q4_k_m)"
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
  double get progress =>
      totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

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

/// Compute backend information.
class BackendInfo {
  BackendInfo({
    required this.name,
    required this.isAvailable,
    this.deviceName,
    this.memoryTotal,
    this.memoryFree,
  });

  /// Backend name (e.g., 'CUDA', 'Metal', 'CPU').
  final String name;

  /// Whether this backend is available.
  final bool isAvailable;

  /// Device name (e.g., 'NVIDIA GeForce RTX 5090').
  final String? deviceName;

  /// Total memory in bytes.
  final int? memoryTotal;

  /// Free memory in bytes.
  final int? memoryFree;

  @override
  String toString() {
    if (!isAvailable) return 'BackendInfo($name: unavailable)';
    final device = deviceName ?? 'unknown device';
    final mem = memoryTotal != null
        ? ' ${(memoryTotal! / 1024 / 1024 / 1024).toStringAsFixed(1)}GB'
        : '';
    return 'BackendInfo($name: $device$mem)';
  }
}

/// Repository for managing llama.cpp models and system operations.
///
/// Provides functionality for:
/// - Discovering GGUF models in directories
/// - Loading and unloading models with pooling
/// - Reading model metadata without full loading
/// - Downloading models from HuggingFace
/// - Querying system capabilities
///
/// Example:
/// ```dart
/// final repo = LlamaCppRepository();
///
/// // Discover models
/// final models = await repo.discoverModels('/path/to/models');
/// for (final model in models) {
///   print('${model.name}: ${model.metadata?.sizeLabel}');
/// }
///
/// // Load a model
/// final loaded = await repo.loadModel('/path/to/model.gguf');
/// print('Loaded: ${loaded.vocabSize} vocab');
///
/// // Download from HuggingFace
/// await for (final progress in repo.downloadModel(
///   'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
///   'qwen2.5-0.5b-instruct-q4_k_m.gguf',
///   '/path/to/models/',
/// )) {
///   print('${progress.progressPercent} downloaded');
/// }
/// ```
class LlamaCppRepository {
  LlamaCppRepository({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  LlamaBindings? _bindings;
  bool _backendInitialized = false;

  // Model pool: path -> (model, refCount)
  final Map<String, (LlamaCppModel, int)> _modelPool = {};

  /// Initialize the llama.cpp backend.
  ///
  /// This is called automatically when loading models.
  void initializeBackend() {
    if (_backendInitialized) return;

    final lib = loadLlamaLibrary();
    _bindings = LlamaBindings(lib);
    _bindings!.llama_backend_init();
    _backendInitialized = true;
  }

  /// Get the native bindings (initializes if needed).
  LlamaBindings get bindings {
    initializeBackend();
    return _bindings!;
  }

  // ============================================================
  // Model Discovery
  // ============================================================

  /// Discover GGUF models in a directory.
  ///
  /// [directory] - Directory to scan for GGUF files.
  /// [recursive] - Whether to scan subdirectories.
  /// [readMetadata] - Whether to read GGUF metadata (slower but more info).
  Future<List<ModelInfo>> discoverModels(
    String directory, {
    bool recursive = false,
    bool readMetadata = true,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      return [];
    }

    final models = <ModelInfo>[];
    final entities = recursive
        ? dir.listSync(recursive: true)
        : dir.listSync();

    for (final entity in entities) {
      if (entity is File && _isGgufFile(entity.path)) {
        try {
          final info = await getModelInfo(entity.path, readMetadata: readMetadata);
          models.add(info);
        } catch (e) {
          // Skip files that can't be read
        }
      }
    }

    return models;
  }

  /// Get information about a specific model file.
  ///
  /// [path] - Path to the GGUF file.
  /// [readMetadata] - Whether to read GGUF metadata.
  Future<ModelInfo> getModelInfo(
    String path, {
    bool readMetadata = true,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }

    final name = _extractModelName(path);
    final fileSize = await file.length();
    final isLoaded = _modelPool.containsKey(path);

    GgufMetadata? metadata;
    if (readMetadata) {
      try {
        metadata = await GgufMetadata.fromFile(path);
      } catch (e) {
        // Metadata reading failed, continue without it
      }
    }

    return ModelInfo(
      path: path,
      name: name,
      fileSize: fileSize,
      metadata: metadata,
      isLoaded: isLoaded,
    );
  }

  /// Check if a file is a valid GGUF model.
  bool isValidModel(String path) {
    return GgufMetadata.isValidGguf(path);
  }

  /// Read metadata from a GGUF file without loading the model.
  Future<GgufMetadata> readMetadata(String path) {
    return GgufMetadata.fromFile(path);
  }

  /// Discover models from common locations.
  ///
  /// Searches:
  /// - ~/.cache/llm_llamacpp/models/
  /// - ~/.ollama/models/blobs/ (Ollama models)
  /// - /usr/share/gguf-models/ (system-wide)
  Future<List<ModelInfo>> discoverCommonLocations({
    bool readMetadata = true,
  }) async {
    final home = Platform.environment['HOME'] ?? '';
    final locations = [
      '$home/.cache/llm_llamacpp/models',
      '$home/.ollama/models/blobs',
      '/usr/share/gguf-models',
      '/usr/local/share/gguf-models',
    ];

    final models = <ModelInfo>[];
    for (final location in locations) {
      if (await Directory(location).exists()) {
        models.addAll(await discoverModels(
          location,
          readMetadata: readMetadata,
        ));
      }
    }

    return models;
  }

  // ============================================================
  // Model Loading/Unloading
  // ============================================================

  /// Load a model with pooling support.
  ///
  /// If the model is already loaded, returns the existing instance
  /// and increments the reference count.
  ///
  /// [path] - Path to the GGUF model file.
  /// [options] - Loading options.
  Future<LlamaCppModel> loadModel(
    String path, {
    ModelLoadOptions options = const ModelLoadOptions(),
  }) async {
    initializeBackend();

    // Check if already loaded
    if (_modelPool.containsKey(path)) {
      final (model, refCount) = _modelPool[path]!;
      _modelPool[path] = (model, refCount + 1);
      return model;
    }

    // Load new model
    final model = LlamaCppModel.load(
      path,
      _bindings!,
      nGpuLayers: options.nGpuLayers,
      useMemoryMap: options.useMemoryMap,
      useMemoryLock: options.useMemoryLock,
      vocabOnly: options.vocabOnly,
    );

    _modelPool[path] = (model, 1);
    return model;
  }

  /// Unload a model.
  ///
  /// If [force] is false, decrements the reference count and only
  /// disposes when count reaches zero. If [force] is true, disposes
  /// immediately regardless of reference count.
  void unloadModel(String path, {bool force = false}) {
    if (!_modelPool.containsKey(path)) return;

    final (model, refCount) = _modelPool[path]!;

    if (force || refCount <= 1) {
      model.dispose();
      _modelPool.remove(path);
    } else {
      _modelPool[path] = (model, refCount - 1);
    }
  }

  /// Unload all models.
  void unloadAllModels() {
    for (final path in _modelPool.keys.toList()) {
      unloadModel(path, force: true);
    }
  }

  /// Get a loaded model by path.
  LlamaCppModel? getLoadedModel(String path) {
    return _modelPool[path]?.$1;
  }

  /// List all loaded models.
  List<String> get loadedModels => _modelPool.keys.toList();

  /// Get reference count for a loaded model.
  int getModelRefCount(String path) {
    return _modelPool[path]?.$2 ?? 0;
  }

  // ============================================================
  // HuggingFace Downloads
  // ============================================================

  /// Download a model from HuggingFace.
  ///
  /// [repoId] - HuggingFace repository ID (e.g., 'Qwen/Qwen2.5-0.5B-Instruct-GGUF').
  /// [filename] - GGUF filename within the repository.
  /// [outputDir] - Directory to save the model.
  /// [revision] - Git revision (branch, tag, or commit). Defaults to 'main'.
  ///
  /// Returns a stream of download progress updates.
  Stream<DownloadProgress> downloadModel(
    String repoId,
    String filename,
    String outputDir, {
    String revision = 'main',
  }) async* {
    final url = 'https://huggingface.co/$repoId/resolve/$revision/$filename';
    final outputPath = '$outputDir/$filename';

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    // Check if file already exists
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final size = await outputFile.length();
      yield DownloadProgress(
        totalBytes: size,
        downloadedBytes: size,
        status: 'Already downloaded',
      );
      return;
    }

    // Start download
    yield DownloadProgress(
      totalBytes: 0,
      downloadedBytes: 0,
      status: 'Starting download...',
    );

    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var downloadedBytes = 0;

    // Create temp file for download
    final tempPath = '$outputPath.download';
    final tempFile = File(tempPath);
    final sink = tempFile.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        yield DownloadProgress(
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          status: 'Downloading...',
        );
      }

      await sink.close();

      // Rename temp file to final name
      await tempFile.rename(outputPath);

      yield DownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        status: 'Complete',
      );
    } catch (e) {
      await sink.close();
      // Clean up temp file on error
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Get download URL for a HuggingFace model.
  String getHuggingFaceUrl(String repoId, String filename,
      {String revision = 'main'}) {
    return 'https://huggingface.co/$repoId/resolve/$revision/$filename';
  }

  /// Parse a HuggingFace model URL.
  ///
  /// Returns (repoId, filename, revision) or null if invalid.
  (String, String, String)? parseHuggingFaceUrl(String url) {
    // https://huggingface.co/{repo_id}/resolve/{revision}/{filename}
    final pattern = RegExp(
      r'https?://huggingface\.co/([^/]+/[^/]+)/resolve/([^/]+)/(.+)',
    );
    final match = pattern.firstMatch(url);
    if (match == null) return null;

    return (match.group(1)!, match.group(3)!, match.group(2)!);
  }

  // ============================================================
  // Model Conversion
  // ============================================================

  /// Create a model converter for converting safetensors to GGUF.
  ///
  /// [llamaCppPath] - Path to llama.cpp repository (optional, will auto-detect).
  ModelConverter createConverter({String? llamaCppPath}) {
    return ModelConverter(
      llamaCppPath: llamaCppPath,
      httpClient: _httpClient,
    );
  }

  /// Convert a HuggingFace model (safetensors) to GGUF format.
  ///
  /// This is a convenience method that creates a converter and runs conversion.
  /// For more control, use [createConverter] directly.
  ///
  /// Example:
  /// ```dart
  /// await for (final progress in repo.convertModel(
  ///   repoId: 'Qwen/Qwen2.5-0.5B-Instruct',
  ///   outputPath: '/path/to/qwen2.5-0.5b-q4.gguf',
  ///   quantization: QuantizationType.q4_k_m,
  /// )) {
  ///   print('${progress.stage}: ${progress.message}');
  /// }
  /// ```
  Stream<ConversionProgress> convertModel({
    required String repoId,
    required String outputPath,
    QuantizationType? quantization,
    String? llamaCppPath,
  }) {
    final converter = createConverter(llamaCppPath: llamaCppPath);
    return converter.convertFromHuggingFace(
      repoId: repoId,
      outputPath: outputPath,
      quantization: quantization,
    );
  }

  /// Check if a HuggingFace repo has GGUF files available.
  ///
  /// Returns list of GGUF filenames, or empty if only safetensors.
  Future<List<String>> checkForGguf(String repoId) async {
    final converter = createConverter();
    return converter.findGgufFiles(repoId);
  }

  /// Get the best model option for a HuggingFace repo.
  ///
  /// Returns a recommendation for how to get the model:
  /// - Direct GGUF download (if available)
  /// - Conversion from safetensors (if only safetensors)
  /// - Error (if neither available)
  Future<ModelAcquisitionPlan> planModelAcquisition(
    String repoId, {
    QuantizationType preferredQuantization = QuantizationType.q4_k_m,
  }) async {
    final converter = createConverter();

    // Check for existing GGUF files
    final ggufFiles = await converter.findGgufFiles(repoId);

    if (ggufFiles.isNotEmpty) {
      // Find best matching quantization
      String? bestMatch;
      for (final file in ggufFiles) {
        final lower = file.toLowerCase();
        if (lower.contains(preferredQuantization.cliName.toLowerCase())) {
          bestMatch = file;
          break;
        }
      }
      bestMatch ??= ggufFiles.first;

      return ModelAcquisitionPlan(
        method: AcquisitionMethod.directDownload,
        repoId: repoId,
        filename: bestMatch,
        availableGgufFiles: ggufFiles,
      );
    }

    // Check for safetensors
    final hasSafetensors = await converter.hasSafetensors(repoId);
    if (hasSafetensors) {
      return ModelAcquisitionPlan(
        method: AcquisitionMethod.convertFromSafetensors,
        repoId: repoId,
        suggestedQuantization: preferredQuantization,
      );
    }

    return ModelAcquisitionPlan(
      method: AcquisitionMethod.notAvailable,
      repoId: repoId,
      error: 'No GGUF or safetensors files found in repository',
    );
  }

  // ============================================================
  // Simplified Model Acquisition (getModel)
  // ============================================================

  /// Get a model from HuggingFace - downloads GGUF or converts safetensors.
  ///
  /// This is the simplified API for acquiring models:
  /// - If the repo has GGUF files, downloads the exact quantization match
  /// - If only safetensors, converts to GGUF (requires [quantization])
  ///
  /// The method is **deterministic** - it will only download exact matches
  /// and throws clear errors when there's ambiguity or no match.
  ///
  /// [repoId] - HuggingFace repo (e.g., 'brynjen/memory_core_extraction').
  /// [outputDir] - Directory to save the model (required).
  /// [quantization] - Target quantization. Required if repo only has safetensors.
  ///                  For GGUF repos, defaults to q4_k_m if not specified.
  /// [preferredFile] - Specific GGUF filename to download (bypasses matching).
  /// [revision] - Git revision (default: 'main').
  /// [llamaCppPath] - Path to llama.cpp for conversion (auto-detected if null).
  ///
  /// Returns the path to the downloaded/converted model.
  ///
  /// Throws:
  /// - [ModelNotFoundException] if no matching GGUF file found
  /// - [AmbiguousModelException] if multiple files match
  /// - [ConversionRequiredException] if only safetensors and no quantization specified
  /// - [UnsupportedModelException] if repo has no usable files
  ///
  /// Example:
  /// ```dart
  /// // GGUF repo - auto-downloads Q4_K_M
  /// final path = await repo.getModel(
  ///   'brynjen/memory_core_extraction',
  ///   outputDir: '/models/',
  /// );
  ///
  /// // Safetensors repo - must specify quantization
  /// final path = await repo.getModel(
  ///   'meta-llama/Llama-3.2-1B',
  ///   outputDir: '/models/',
  ///   quantization: QuantizationType.q4_k_m,
  /// );
  ///
  /// // Specific file
  /// final path = await repo.getModel(
  ///   'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  ///   outputDir: '/models/',
  ///   preferredFile: 'qwen2.5-0.5b-instruct-q8_0.gguf',
  /// );
  /// ```
  Future<String> getModel(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
    String? llamaCppPath,
  }) async {
    // Use streaming version and collect result
    String? resultPath;
    
    await for (final status in getModelStream(
      repoId,
      outputDir: outputDir,
      quantization: quantization,
      preferredFile: preferredFile,
      revision: revision,
      llamaCppPath: llamaCppPath,
    )) {
      if (status.isError) {
        throw Exception(status.error ?? 'Model acquisition failed');
      }
      if (status.isComplete) {
        resultPath = status.modelPath;
      }
    }

    if (resultPath == null) {
      throw Exception('Model acquisition completed but no path returned');
    }

    return resultPath;
  }

  /// Stream version of [getModel] with progress updates.
  ///
  /// Use this for UI progress feedback or long-running downloads.
  ///
  /// Example:
  /// ```dart
  /// await for (final status in repo.getModelStream(
  ///   'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  ///   outputDir: '/models/',
  /// )) {
  ///   print('${status.stage.name}: ${status.message}');
  ///   if (status.progress != null) {
  ///     print('  Progress: ${status.progressPercent}');
  ///   }
  ///   if (status.isComplete) {
  ///     print('Ready: ${status.modelPath}');
  ///   }
  /// }
  /// ```
  Stream<ModelAcquisitionStatus> getModelStream(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
    String? llamaCppPath,
  }) async* {
    // Default to q4_k_m for GGUF matching if not specified
    final targetQuant = quantization ?? QuantizationType.q4_k_m;

    yield ModelAcquisitionStatus(
      stage: ModelAcquisitionStage.checking,
      message: 'Checking repository files...',
    );

    // List files in the repository
    final converter = createConverter(llamaCppPath: llamaCppPath);
    List<HfModelFile> files;
    try {
      files = await converter.listRepoFiles(repoId, revision: revision);
    } catch (e) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.failed,
        message: 'Failed to list repository files',
        error: e.toString(),
      );
      return;
    }

    final ggufFiles = files
        .where((f) => f.filename.toLowerCase().endsWith('.gguf'))
        .toList();
    final hasSafetensors = files.any((f) => f.filename.endsWith('.safetensors'));

    // CASE 1: Specific file requested
    if (preferredFile != null) {
      final match = ggufFiles.where((f) => f.filename == preferredFile).toList();
      if (match.isEmpty) {
        throw ModelNotFoundException(
          repoId: repoId,
          message: "File '$preferredFile' not found in repository",
          availableFiles: ggufFiles.map((f) => f.filename).toList(),
        );
      }

      yield* _downloadGgufFile(
        repoId: repoId,
        filename: preferredFile,
        outputDir: outputDir,
        revision: revision,
      );
      return;
    }

    // CASE 2: Repository has GGUF files
    if (ggufFiles.isNotEmpty) {
      // Find exact quantization match
      final quantPattern = RegExp(targetQuant.cliName, caseSensitive: false);
      final matches = ggufFiles
          .where((f) => quantPattern.hasMatch(f.filename))
          .toList();

      if (matches.isEmpty) {
        throw ModelNotFoundException(
          repoId: repoId,
          message: 'No ${targetQuant.displayName} GGUF found',
          availableFiles: ggufFiles.map((f) => 
            '${f.filename} (${_formatSize(f.size)})'
          ).toList(),
        );
      }

      if (matches.length > 1) {
        throw AmbiguousModelException(
          repoId: repoId,
          message: 'Multiple ${targetQuant.displayName} files found',
          matchingFiles: matches.map((f) => f.filename).toList(),
        );
      }

      // Single exact match - download it
      yield* _downloadGgufFile(
        repoId: repoId,
        filename: matches.first.filename,
        outputDir: outputDir,
        revision: revision,
        fileSize: matches.first.size,
      );
      return;
    }

    // CASE 3: Only safetensors - conversion required
    if (hasSafetensors) {
      // Quantization must be explicitly specified for conversion
      if (quantization == null) {
        throw ConversionRequiredException(
          repoId: repoId,
          message: 'Quantization required for safetensors conversion',
        );
      }

      yield* _convertFromSafetensors(
        repoId: repoId,
        outputDir: outputDir,
        quantization: quantization,
        revision: revision,
        llamaCppPath: llamaCppPath,
      );
      return;
    }

    // CASE 4: No usable files
    throw UnsupportedModelException(
      repoId: repoId,
      message: 'Repository has no GGUF or safetensors files',
    );
  }

  /// Download a specific GGUF file from HuggingFace.
  Stream<ModelAcquisitionStatus> _downloadGgufFile({
    required String repoId,
    required String filename,
    required String outputDir,
    required String revision,
    int? fileSize,
  }) async* {
    final outputPath = '$outputDir/$filename';

    // Check if already exists
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final existingSize = await outputFile.length();
      if (fileSize == null || existingSize == fileSize) {
        yield ModelAcquisitionStatus(
          stage: ModelAcquisitionStage.complete,
          message: 'Model already downloaded',
          modelPath: outputPath,
        );
        return;
      }
    }

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    yield ModelAcquisitionStatus(
      stage: ModelAcquisitionStage.downloading,
      message: 'Downloading $filename...',
      progress: 0.0,
    );

    // Download the file
    await for (final progress in downloadModel(
      repoId,
      filename,
      outputDir,
      revision: revision,
    )) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.downloading,
        message: progress.status ?? 'Downloading...',
        progress: progress.progress,
      );

      if (progress.isComplete) {
        yield ModelAcquisitionStatus(
          stage: ModelAcquisitionStage.complete,
          message: 'Download complete',
          modelPath: outputPath,
        );
      }
    }
  }

  /// Convert safetensors to GGUF with specified quantization.
  Stream<ModelAcquisitionStatus> _convertFromSafetensors({
    required String repoId,
    required String outputDir,
    required QuantizationType quantization,
    required String revision,
    String? llamaCppPath,
  }) async* {
    // Generate output filename
    final repoName = repoId.split('/').last.toLowerCase();
    final outputFilename = '$repoName-${quantization.cliName}.gguf';
    final outputPath = '$outputDir/$outputFilename';

    // Check if already exists
    if (await File(outputPath).exists()) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.complete,
        message: 'Converted model already exists',
        modelPath: outputPath,
      );
      return;
    }

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    // Run conversion
    await for (final progress in convertModel(
      repoId: repoId,
      outputPath: outputPath,
      quantization: quantization,
      llamaCppPath: llamaCppPath,
    )) {
      final stage = switch (progress.stage) {
        ConversionStage.checking => ModelAcquisitionStage.checking,
        ConversionStage.downloading => ModelAcquisitionStage.downloading,
        ConversionStage.converting => ModelAcquisitionStage.converting,
        ConversionStage.quantizing => ModelAcquisitionStage.quantizing,
        ConversionStage.cleanup => ModelAcquisitionStage.converting,
        ConversionStage.complete => ModelAcquisitionStage.complete,
        ConversionStage.failed => ModelAcquisitionStage.failed,
      };

      yield ModelAcquisitionStatus(
        stage: stage,
        message: progress.message,
        progress: progress.progress,
        modelPath: progress.isComplete ? outputPath : null,
        error: progress.error,
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  // ============================================================
  // System Information
  // ============================================================

  /// Get available compute backends.
  List<BackendInfo> getAvailableBackends() {
    final backends = <BackendInfo>[];

    // CPU is always available
    backends.add(BackendInfo(
      name: 'CPU',
      isAvailable: true,
      deviceName: Platform.operatingSystem,
    ));

    // Check for CUDA (Linux/Windows)
    if (Platform.isLinux || Platform.isWindows) {
      final hasCuda = _checkCudaAvailable();
      backends.add(BackendInfo(
        name: 'CUDA',
        isAvailable: hasCuda,
        deviceName: hasCuda ? _getCudaDeviceName() : null,
      ));
    }

    // Check for Metal (macOS)
    if (Platform.isMacOS) {
      backends.add(BackendInfo(
        name: 'Metal',
        isAvailable: true, // Metal is always available on modern macOS
        deviceName: 'Apple Silicon / AMD GPU',
      ));
    }

    // Check for Vulkan
    final hasVulkan = _checkVulkanAvailable();
    backends.add(BackendInfo(
      name: 'Vulkan',
      isAvailable: hasVulkan,
    ));

    return backends;
  }

  /// Get the default model cache directory.
  String get defaultCacheDirectory {
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isLinux || Platform.isMacOS) {
      return '$home/.cache/llm_llamacpp/models';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'] ?? '';
      return '$appData/llm_llamacpp/models';
    }
    return '$home/.cache/llm_llamacpp/models';
  }

  /// Get the default number of GPU layers based on system.
  int get recommendedGpuLayers {
    final backends = getAvailableBackends();
    if (backends.any((b) => b.name == 'CUDA' && b.isAvailable)) {
      return 99; // Offload all layers
    }
    if (backends.any((b) => b.name == 'Metal' && b.isAvailable)) {
      return 99; // Offload all layers
    }
    return 0; // CPU only
  }

  // ============================================================
  // Cleanup
  // ============================================================

  /// Dispose of all resources.
  void dispose() {
    unloadAllModels();
    if (_backendInitialized && _bindings != null) {
      _bindings!.llama_backend_free();
      _backendInitialized = false;
    }
    _httpClient.close();
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  bool _isGgufFile(String path) {
    final lower = path.toLowerCase();
    if (!lower.endsWith('.gguf')) {
      // Also check Ollama blob format (sha256-...)
      if (!path.contains('sha256-')) return false;
    }
    return GgufMetadata.isValidGguf(path);
  }

  String _extractModelName(String path) {
    final filename = path.split(Platform.pathSeparator).last;

    // Handle Ollama blob format
    if (filename.startsWith('sha256-')) {
      return 'ollama-${filename.substring(7, 15)}...';
    }

    // Remove .gguf extension
    if (filename.toLowerCase().endsWith('.gguf')) {
      return filename.substring(0, filename.length - 5);
    }

    return filename;
  }

  bool _checkCudaAvailable() {
    // Check for CUDA libraries
    final cudaPaths = [
      '/usr/local/cuda/lib64/libcudart.so',
      '/usr/lib/x86_64-linux-gnu/libcuda.so',
      '/usr/lib/libcuda.so',
    ];

    for (final path in cudaPaths) {
      if (File(path).existsSync()) return true;
    }

    // Check nvidia-smi
    try {
      final result = Process.runSync('nvidia-smi', ['--query']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  String? _getCudaDeviceName() {
    try {
      final result = Process.runSync(
        'nvidia-smi',
        ['--query-gpu=name', '--format=csv,noheader'],
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().split('\n').first;
      }
    } catch (e) {
      // nvidia-smi not available
    }
    return null;
  }

  bool _checkVulkanAvailable() {
    // Check for Vulkan libraries
    final vulkanPaths = [
      '/usr/lib/x86_64-linux-gnu/libvulkan.so.1',
      '/usr/lib/libvulkan.so.1',
    ];

    for (final path in vulkanPaths) {
      if (File(path).existsSync()) return true;
    }

    return false;
  }
}

