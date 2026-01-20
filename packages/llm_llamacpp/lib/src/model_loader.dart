import 'bindings/llama_bindings.dart';
import 'llamacpp_model.dart';
import 'loader/loader.dart';

/// Manages loading and unloading of llama.cpp models with pooling support.
///
/// Models are pooled by path - if the same model is loaded multiple times,
/// the existing instance is returned with an incremented reference count.
class LlamaCppModelLoader {
  LlamaCppModelLoader({LlamaBindings? bindings}) : _bindings = bindings;

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

  /// Whether the backend has been initialized.
  bool get isBackendInitialized => _backendInitialized;

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

  /// List all loaded model paths.
  List<String> get loadedModels => _modelPool.keys.toList();

  /// Get reference count for a loaded model.
  int getModelRefCount(String path) {
    return _modelPool[path]?.$2 ?? 0;
  }

  /// Check if a model is currently loaded.
  bool isModelLoaded(String path) {
    return _modelPool.containsKey(path);
  }

  /// Dispose of the loader and all loaded models.
  void dispose() {
    unloadAllModels();
    if (_backendInitialized && _bindings != null) {
      _bindings!.llama_backend_free();
      _backendInitialized = false;
    }
  }
}
