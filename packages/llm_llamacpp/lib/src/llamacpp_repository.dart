import 'dart:async';

import 'package:http/http.dart' as http;

import 'backend_info.dart';
import 'bindings/llama_bindings.dart';
import 'huggingface_client.dart';
import 'llamacpp_model.dart';
import 'lora_adapter.dart';
import 'model_converter.dart';
import 'model_discovery.dart';
import 'model_info.dart';
import 'model_loader.dart';

// Re-export components for convenience
export 'backend_info.dart';
export 'exceptions.dart';
export 'huggingface_client.dart' show HuggingFaceClient;
export 'lora_adapter.dart';
export 'model_discovery.dart' show LlamaCppModelDiscovery;
export 'model_info.dart';
export 'model_loader.dart' show LlamaCppModelLoader;

/// Repository for managing llama.cpp models and system operations.
///
/// This is a facade that coordinates the following components:
/// - [LlamaCppModelLoader] - Model loading/unloading with pooling
/// - [LlamaCppModelDiscovery] - Finding models in directories
/// - [HuggingFaceClient] - Downloading from HuggingFace
/// - [LoraManager] - LoRA adapter management
///
/// For more granular control, you can use the individual components directly.
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
/// // Load and apply a LoRA adapter
/// final lora = repo.loadLora('/path/to/lora.gguf', loaded);
/// print('LoRA loaded: ${lora.metadataCount} metadata entries');
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
    String? llamaCppPath,
  })  : _httpClient = httpClient ?? http.Client(),
        _llamaCppPath = llamaCppPath {
    _loader = LlamaCppModelLoader();
    _discovery = LlamaCppModelDiscovery();
    _hfClient = HuggingFaceClient(
      httpClient: _httpClient,
      llamaCppPath: _llamaCppPath,
    );
  }

  final http.Client _httpClient;
  final String? _llamaCppPath;

  late final LlamaCppModelLoader _loader;
  late final LlamaCppModelDiscovery _discovery;
  late final HuggingFaceClient _hfClient;
  LoraManager? _loraManager;

  // ============================================================
  // Backend Access
  // ============================================================

  /// Initialize the llama.cpp backend.
  ///
  /// This is called automatically when loading models.
  void initializeBackend() => _loader.initializeBackend();

  /// Get the native bindings (initializes if needed).
  LlamaBindings get bindings => _loader.bindings;

  /// Whether the backend has been initialized.
  bool get isBackendInitialized => _loader.isBackendInitialized;

  // ============================================================
  // Model Discovery (delegates to LlamaCppModelDiscovery)
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
  }) {
    _discovery.updateLoadedPaths(_loader.loadedModels.toSet());
    return _discovery.discoverModels(
      directory,
      recursive: recursive,
      readMetadata: readMetadata,
    );
  }

  /// Get information about a specific model file.
  Future<ModelInfo> getModelInfo(String path, {bool readMetadata = true}) {
    _discovery.updateLoadedPaths(_loader.loadedModels.toSet());
    return _discovery.getModelInfo(path, readMetadata: readMetadata);
  }

  /// Check if a file is a valid GGUF model.
  bool isValidModel(String path) => _discovery.isValidModel(path);

  /// Read metadata from a GGUF file without loading the model.
  Future<dynamic> readMetadata(String path) => _discovery.readMetadata(path);

  /// Discover models from common locations.
  Future<List<ModelInfo>> discoverCommonLocations({bool readMetadata = true}) {
    _discovery.updateLoadedPaths(_loader.loadedModels.toSet());
    return _discovery.discoverCommonLocations(readMetadata: readMetadata);
  }

  // ============================================================
  // Model Loading/Unloading (delegates to LlamaCppModelLoader)
  // ============================================================

  /// Load a model with pooling support.
  ///
  /// If the model is already loaded, returns the existing instance
  /// and increments the reference count.
  Future<LlamaCppModel> loadModel(
    String path, {
    ModelLoadOptions options = const ModelLoadOptions(),
  }) =>
      _loader.loadModel(path, options: options);

  /// Unload a model.
  ///
  /// If [force] is false, decrements the reference count and only
  /// disposes when count reaches zero.
  void unloadModel(String path, {bool force = false}) =>
      _loader.unloadModel(path, force: force);

  /// Unload all models.
  void unloadAllModels() => _loader.unloadAllModels();

  /// Get a loaded model by path.
  LlamaCppModel? getLoadedModel(String path) => _loader.getLoadedModel(path);

  /// List all loaded model paths.
  List<String> get loadedModels => _loader.loadedModels;

  /// Get reference count for a loaded model.
  int getModelRefCount(String path) => _loader.getModelRefCount(path);

  // ============================================================
  // LoRA Management (delegates to LoraManager)
  // ============================================================

  /// Get the LoRA manager (creates if needed).
  LoraManager get loraManager {
    _loraManager ??= LoraManager(bindings);
    return _loraManager!;
  }

  /// Load a LoRA adapter from file.
  ///
  /// [path] - Path to the LoRA GGUF file.
  /// [model] - The base model this LoRA is for.
  LlamaLoraAdapter loadLora(String path, LlamaCppModel model) =>
      loraManager.loadLora(path, model);

  /// Unload a LoRA adapter.
  void unloadLora(LlamaLoraAdapter lora, {bool force = false}) =>
      loraManager.unloadLora(lora, force: force);

  /// Unload all LoRA adapters.
  void unloadAllLoras() => loraManager.unloadAllLoras();

  /// Get a loaded LoRA by path.
  LlamaLoraAdapter? getLoadedLora(String path) => loraManager.getLoadedLora(path);

  /// List all loaded LoRA paths.
  List<String> get loadedLoras => loraManager.loadedLoras;

  // ============================================================
  // HuggingFace Downloads (delegates to HuggingFaceClient)
  // ============================================================

  /// Download a model from HuggingFace.
  Stream<DownloadProgress> downloadModel(
    String repoId,
    String filename,
    String outputDir, {
    String revision = 'main',
  }) =>
      _hfClient.downloadModel(repoId, filename, outputDir, revision: revision);

  /// Get download URL for a HuggingFace model.
  String getHuggingFaceUrl(String repoId, String filename,
          {String revision = 'main'}) =>
      _hfClient.getHuggingFaceUrl(repoId, filename, revision: revision);

  /// Parse a HuggingFace model URL.
  (String, String, String)? parseHuggingFaceUrl(String url) =>
      _hfClient.parseHuggingFaceUrl(url);

  // ============================================================
  // Model Conversion
  // ============================================================

  /// Create a model converter for converting safetensors to GGUF.
  ModelConverter createConverter({String? llamaCppPath}) {
    return ModelConverter(
      llamaCppPath: llamaCppPath ?? _llamaCppPath,
      httpClient: _httpClient,
    );
  }

  /// Convert a HuggingFace model (safetensors) to GGUF format.
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
  Future<List<String>> checkForGguf(String repoId) =>
      _hfClient.checkForGguf(repoId);

  /// Get the best model option for a HuggingFace repo.
  Future<ModelAcquisitionPlan> planModelAcquisition(
    String repoId, {
    QuantizationType preferredQuantization = QuantizationType.q4_k_m,
  }) =>
      _hfClient.planModelAcquisition(
        repoId,
        preferredQuantization: preferredQuantization,
      );

  // ============================================================
  // Simplified Model Acquisition
  // ============================================================

  /// Get a model from HuggingFace - downloads GGUF or converts safetensors.
  Future<String> getModel(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
    String? llamaCppPath,
  }) =>
      _hfClient.getModel(
        repoId,
        outputDir: outputDir,
        quantization: quantization,
        preferredFile: preferredFile,
        revision: revision,
      );

  /// Stream version of [getModel] with progress updates.
  Stream<ModelAcquisitionStatus> getModelStream(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
  }) =>
      _hfClient.getModelStream(
        repoId,
        outputDir: outputDir,
        quantization: quantization,
        preferredFile: preferredFile,
        revision: revision,
      );

  // ============================================================
  // System Information
  // ============================================================

  /// Get available compute backends.
  List<BackendInfo> getAvailableBackends() =>
      BackendDetector.getAvailableBackends();

  /// Get the default model cache directory.
  String get defaultCacheDirectory => BackendDetector.getDefaultCacheDirectory();

  /// Get the default number of GPU layers based on system.
  int get recommendedGpuLayers => BackendDetector.getRecommendedGpuLayers();

  // ============================================================
  // Cleanup
  // ============================================================

  /// Dispose of all resources.
  void dispose() {
    _loraManager?.dispose();
    _loader.dispose();
    _hfClient.close();
    _httpClient.close();
  }
}
