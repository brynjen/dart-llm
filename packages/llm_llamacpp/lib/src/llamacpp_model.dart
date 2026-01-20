import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';

/// Represents a loaded llama.cpp model.
///
/// Models are loaded from GGUF files and can be used with multiple contexts.
class LlamaCppModel {
  LlamaCppModel._({
    required this.path,
    required Pointer<llama_model> modelPtr,
    required LlamaBindings bindings,
  }) : _modelPtr = modelPtr,
       _bindings = bindings;

  /// The path to the GGUF model file.
  final String path;

  final Pointer<llama_model> _modelPtr;
  final LlamaBindings _bindings;

  bool _disposed = false;

  /// Returns the internal model pointer.
  ///
  /// This should only be used by internal code.
  Pointer<llama_model> get pointer {
    _checkNotDisposed();
    return _modelPtr;
  }

  /// Gets the vocabulary from the model.
  Pointer<llama_vocab> get vocab {
    _checkNotDisposed();
    return _bindings.llama_model_get_vocab(_modelPtr);
  }

  /// Gets the vocabulary size.
  int get vocabSize {
    _checkNotDisposed();
    return _bindings.llama_n_vocab(vocab);
  }

  /// Gets the training context size.
  int get contextSizeTrain {
    _checkNotDisposed();
    return _bindings.llama_n_ctx_train(_modelPtr);
  }

  /// Gets the embedding dimension.
  int get embeddingSize {
    _checkNotDisposed();
    return _bindings.llama_n_embd(_modelPtr);
  }

  /// Gets the beginning-of-sequence token.
  int get bosToken {
    _checkNotDisposed();
    return _bindings.llama_token_bos(vocab);
  }

  /// Gets the end-of-sequence token.
  int get eosToken {
    _checkNotDisposed();
    return _bindings.llama_token_eos(vocab);
  }

  /// Gets the newline token.
  int get nlToken {
    _checkNotDisposed();
    return _bindings.llama_token_nl(vocab);
  }

  /// Gets the padding token.
  int get padToken {
    _checkNotDisposed();
    return _bindings.llama_token_pad(vocab);
  }

  /// Checks if a token is an end-of-generation token.
  bool isEogToken(int token) {
    _checkNotDisposed();
    return _bindings.llama_vocab_is_eog(vocab, token);
  }

  /// Checks if a token is a control token.
  bool isControlToken(int token) {
    _checkNotDisposed();
    return _bindings.llama_vocab_is_control(vocab, token);
  }

  /// Releases the model resources.
  void dispose() {
    if (!_disposed) {
      _bindings.llama_free_model(_modelPtr);
      _disposed = true;
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Model has been disposed');
    }
  }

  /// Loads a model from a GGUF file.
  static LlamaCppModel load(
    String path,
    LlamaBindings bindings, {
    int nGpuLayers = 0,
    bool useMemoryMap = true,
    bool useMemoryLock = false,
    bool vocabOnly = false,
  }) {
    final params = bindings.llama_model_default_params();
    params.n_gpu_layers = nGpuLayers;
    params.use_mmap = useMemoryMap;
    params.use_mlock = useMemoryLock;
    params.vocab_only = vocabOnly;

    final pathPtr = path.toNativeUtf8();
    try {
      final modelPtr = bindings.llama_load_model_from_file(
        pathPtr.cast(),
        params,
      );

      if (modelPtr == nullptr) {
        throw Exception('Failed to load model from: $path');
      }

      return LlamaCppModel._(
        path: path,
        modelPtr: modelPtr,
        bindings: bindings,
      );
    } finally {
      calloc.free(pathPtr);
    }
  }
}

/// Options for model loading.
class ModelLoadOptions {
  const ModelLoadOptions({
    this.nGpuLayers = 0,
    this.useMemoryMap = true,
    this.useMemoryLock = false,
    this.vocabOnly = false,
  });

  /// Number of layers to offload to GPU.
  final int nGpuLayers;

  /// Whether to use memory-mapped files.
  final bool useMemoryMap;

  /// Whether to lock model in memory.
  final bool useMemoryLock;

  /// Whether to load only vocabulary (for tokenization).
  final bool vocabOnly;
}
