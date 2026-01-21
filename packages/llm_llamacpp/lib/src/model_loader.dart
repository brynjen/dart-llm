import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:llm_core/llm_core.dart' show ModelLoadException;
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/llamacpp_model.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';

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
    
    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files
    try {
      final ggmlBackendLoadAll = lib.lookupFunction<
          ffi.Void Function(),
          void Function()>('ggml_backend_load_all');
      ggmlBackendLoadAll();
    } catch (e) {
      // If ggml_backend_load_all is not available, try ggml_backend_load_all_from_path
      // On Android, libraries are in the app's native library directory
      try {
        final ggmlBackendLoadAllFromPath = lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Char>),
            void Function(ffi.Pointer<ffi.Char>)>('ggml_backend_load_all_from_path');
        // Pass null to search default paths (where .so files are located)
        ggmlBackendLoadAllFromPath(ffi.Pointer.fromAddress(0));
      } catch (e2) {
        // If neither is available, log a warning but continue
        // The backends might be statically linked or the function might not be exported
        print('[llm_llamacpp] Warning: Could not load backends dynamically: $e2');
        print('[llm_llamacpp] This may cause model loading to fail if backends are not statically linked');
      }
    }
    
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

    // Validate model path exists
    final file = File(path);
    if (!await file.exists()) {
      throw ModelLoadException(
        'Model file not found: $path',
        modelPath: path,
      );
    }

    // Validate file size (should not be empty)
    final size = await file.length();
    if (size == 0) {
      throw ModelLoadException(
        'Model file is empty (0 bytes): $path\n'
        'The file may have been corrupted during download. Please try downloading again.',
        modelPath: path,
      );
    }

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
