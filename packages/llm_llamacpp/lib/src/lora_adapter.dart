import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/llamacpp_model.dart';

/// Represents a loaded LoRA adapter.
///
/// LoRA (Low-Rank Adaptation) adapters allow fine-tuning a base model
/// without modifying its weights. They are loaded against a specific model
/// and can be applied to contexts with a scale factor.
///
/// Example:
/// ```dart
/// final model = await modelLoader.loadModel('/path/to/model.gguf');
/// final lora = loraManager.loadLora('/path/to/lora.gguf', model);
///
/// // Apply to context with full strength
/// loraManager.applyLora(contextPtr, lora, scale: 1.0);
///
/// // Or with reduced strength
/// loraManager.applyLora(contextPtr, lora, scale: 0.5);
/// ```
class LlamaLoraAdapter {
  LlamaLoraAdapter._({
    required this.path,
    required this._pointer,
    required this._bindings,
  });

  /// Path to the LoRA adapter file.
  final String path;

  final Pointer<llama_adapter_lora> _pointer;
  final LlamaBindings _bindings;

  bool _disposed = false;

  /// Returns the internal adapter pointer.
  ///
  /// This should only be used by internal code.
  Pointer<llama_adapter_lora> get pointer {
    _checkNotDisposed();
    return _pointer;
  }

  /// Whether this adapter has been disposed.
  bool get isDisposed => _disposed;

  /// Get the number of metadata entries in the adapter.
  int get metadataCount {
    _checkNotDisposed();
    return _bindings.llama_adapter_meta_count(_pointer);
  }

  /// Get a metadata value by key.
  String? getMetadataValue(String key) {
    _checkNotDisposed();
    final keyPtr = key.toNativeUtf8();
    const bufSize = 256;
    final buf = calloc<Char>(bufSize);

    try {
      final len = _bindings.llama_adapter_meta_val_str(
        _pointer,
        keyPtr.cast(),
        buf,
        bufSize,
      );

      if (len < 0) return null;
      return buf.cast<Utf8>().toDartString(length: len);
    } finally {
      calloc.free(keyPtr);
      calloc.free(buf);
    }
  }

  /// Get a metadata key by index.
  String? getMetadataKeyByIndex(int index) {
    _checkNotDisposed();
    const bufSize = 256;
    final buf = calloc<Char>(bufSize);

    try {
      final len = _bindings.llama_adapter_meta_key_by_index(
        _pointer,
        index,
        buf,
        bufSize,
      );

      if (len < 0) return null;
      return buf.cast<Utf8>().toDartString(length: len);
    } finally {
      calloc.free(buf);
    }
  }

  /// Get a metadata value by index.
  String? getMetadataValueByIndex(int index) {
    _checkNotDisposed();
    const bufSize = 256;
    final buf = calloc<Char>(bufSize);

    try {
      final len = _bindings.llama_adapter_meta_val_str_by_index(
        _pointer,
        index,
        buf,
        bufSize,
      );

      if (len < 0) return null;
      return buf.cast<Utf8>().toDartString(length: len);
    } finally {
      calloc.free(buf);
    }
  }

  /// Get all metadata as a map.
  Map<String, String> getAllMetadata() {
    _checkNotDisposed();
    final result = <String, String>{};
    final count = metadataCount;

    for (var i = 0; i < count; i++) {
      final key = getMetadataKeyByIndex(i);
      final value = getMetadataValueByIndex(i);
      if (key != null && value != null) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Check if this is an aLoRA (adaptive LoRA) with invocation tokens.
  bool get isALoRA {
    _checkNotDisposed();
    return _bindings.llama_adapter_get_alora_n_invocation_tokens(_pointer) > 0;
  }

  /// Get the number of aLoRA invocation tokens.
  int get aLoRAInvocationTokenCount {
    _checkNotDisposed();
    return _bindings.llama_adapter_get_alora_n_invocation_tokens(_pointer);
  }

  /// Releases the adapter resources.
  void dispose() {
    if (!_disposed) {
      _bindings.llama_adapter_lora_free(_pointer);
      _disposed = true;
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('LoRA adapter has been disposed');
    }
  }

  @override
  String toString() {
    if (_disposed) return 'LlamaLoraAdapter(disposed)';
    return 'LlamaLoraAdapter($path, metadata: $metadataCount entries)';
  }
}

/// Manages LoRA adapters for llama.cpp models.
///
/// Provides functionality for:
/// - Loading LoRA adapters from files
/// - Applying LoRAs to contexts with scale factors
/// - Switching between LoRAs on a context
/// - Pooling loaded LoRAs for reuse
///
/// Example:
/// ```dart
/// final loraManager = LoraManager(bindings);
///
/// // Load a LoRA adapter
/// final lora = loraManager.loadLora('/path/to/lora.gguf', model);
///
/// // Apply to a context
/// loraManager.applyLora(ctx, lora, scale: 0.8);
///
/// // Switch to a different LoRA
/// final otherLora = loraManager.loadLora('/path/to/other.gguf', model);
/// loraManager.switchLora(ctx, otherLora, scale: 1.0);
///
/// // Remove all LoRAs
/// loraManager.clearLoras(ctx);
///
/// // Cleanup
/// loraManager.unloadLora(lora);
/// loraManager.unloadLora(otherLora);
/// ```
class LoraManager {
  LoraManager(this._bindings);

  final LlamaBindings _bindings;

  // LoRA pool: path -> (adapter, refCount)
  final Map<String, (LlamaLoraAdapter, int)> _loraPool = {};

  /// The LoRA set currently applied to each context, keyed by context address.
  ///
  /// Upstream llama.cpp replaced the incremental `llama_set_adapter_lora` /
  /// `llama_rm_adapter_lora` / `llama_clear_adapter_lora` trio with a single
  /// declarative `llama_set_adapters_lora`, which replaces a context's entire
  /// adapter set on every call. To keep offering incremental add/remove we have
  /// to track what is applied and re-send the whole list after each mutation.
  ///
  /// Insertion order is preserved so adapters are re-applied in the order they
  /// were added.
  final Map<int, List<(LlamaLoraAdapter, double)>> _activeLoras = {};

  /// Load a LoRA adapter from file.
  ///
  /// [path] - Path to the LoRA GGUF file.
  /// [model] - The base model this LoRA is for.
  ///
  /// If the LoRA is already loaded, returns the existing instance
  /// and increments the reference count.
  ///
  /// Throws [LoraLoadException] if loading fails.
  LlamaLoraAdapter loadLora(String path, LlamaCppModel model) {
    // Check if already loaded
    if (_loraPool.containsKey(path)) {
      final (adapter, refCount) = _loraPool[path]!;
      _loraPool[path] = (adapter, refCount + 1);
      return adapter;
    }

    // Load new LoRA
    final pathPtr = path.toNativeUtf8();
    try {
      final adapterPtr = _bindings.llama_adapter_lora_init(
        model.pointer,
        pathPtr.cast(),
      );

      if (adapterPtr == nullptr) {
        throw LoraLoadException(
          path: path,
          message: 'Failed to load LoRA adapter',
        );
      }

      final adapter = LlamaLoraAdapter._(
        path: path,
        pointer: adapterPtr,
        bindings: _bindings,
      );

      _loraPool[path] = (adapter, 1);
      return adapter;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Pushes the tracked adapter set for [ctx] down to llama.cpp.
  ///
  /// Returns 0 on success, negative on error.
  int _syncAdapters(Pointer<llama_context> ctx) {
    final active = _activeLoras[ctx.address];

    if (active == null || active.isEmpty) {
      _activeLoras.remove(ctx.address);
      return _bindings.llama_set_adapters_lora(ctx, nullptr, 0, nullptr);
    }

    final adapters = calloc<Pointer<llama_adapter_lora>>(active.length);
    final scales = calloc<Float>(active.length);
    try {
      for (var i = 0; i < active.length; i++) {
        adapters[i] = active[i].$1.pointer;
        scales[i] = active[i].$2;
      }
      return _bindings.llama_set_adapters_lora(
        ctx,
        adapters,
        active.length,
        scales,
      );
    } finally {
      calloc.free(adapters);
      calloc.free(scales);
    }
  }

  /// Apply a LoRA adapter to a context.
  ///
  /// [ctx] - The llama context to apply the LoRA to.
  /// [lora] - The LoRA adapter to apply.
  /// [scale] - Scale factor (0.0 to 1.0+). Default is 1.0.
  ///
  /// Multiple LoRAs can be applied to the same context with different scales.
  /// Applying an adapter that is already active updates its scale in place
  /// rather than adding it twice.
  ///
  /// Returns 0 on success, negative on error.
  int applyLora(
    Pointer<llama_context> ctx,
    LlamaLoraAdapter lora, {
    double scale = 1.0,
  }) {
    final active = _activeLoras.putIfAbsent(ctx.address, () => []);
    final existing = active.indexWhere((e) => e.$1.path == lora.path);
    if (existing >= 0) {
      active[existing] = (lora, scale);
    } else {
      active.add((lora, scale));
    }
    return _syncAdapters(ctx);
  }

  /// Remove a specific LoRA adapter from a context.
  ///
  /// [ctx] - The llama context.
  /// [lora] - The LoRA adapter to remove.
  ///
  /// Returns 0 on success, negative on error. Removing an adapter that is not
  /// applied is a no-op and returns 0.
  int removeLora(Pointer<llama_context> ctx, LlamaLoraAdapter lora) {
    final active = _activeLoras[ctx.address];
    if (active == null) return 0;
    final before = active.length;
    active.removeWhere((e) => e.$1.path == lora.path);
    if (active.length == before) return 0;
    return _syncAdapters(ctx);
  }

  /// Remove all LoRA adapters from a context.
  ///
  /// [ctx] - The llama context to clear LoRAs from.
  void clearLoras(Pointer<llama_context> ctx) {
    _activeLoras.remove(ctx.address);
    _syncAdapters(ctx);
  }

  /// Switch to a different LoRA on a context.
  ///
  /// Replaces whatever is currently applied with just [lora]. Pass null to
  /// clear all LoRAs.
  ///
  /// [ctx] - The llama context.
  /// [lora] - The new LoRA to apply, or null to just clear.
  /// [scale] - Scale factor for the new LoRA.
  void switchLora(
    Pointer<llama_context> ctx,
    LlamaLoraAdapter? lora, {
    double scale = 1.0,
  }) {
    // Applied as a single native call rather than clear-then-apply, so the
    // context never transiently loses its adapters.
    if (lora == null) {
      _activeLoras.remove(ctx.address);
    } else {
      _activeLoras[ctx.address] = [(lora, scale)];
    }
    _syncAdapters(ctx);
  }

  /// The LoRAs currently applied to [ctx], in application order.
  List<LoraConfig> activeLoras(Pointer<llama_context> ctx) => [
    for (final (adapter, scale)
        in _activeLoras[ctx.address] ?? const <(LlamaLoraAdapter, double)>[])
      LoraConfig(path: adapter.path, scale: scale),
  ];

  /// Drop the tracked adapter set for [ctx] without touching the context.
  ///
  /// Call this right before freeing a context. Contexts are tracked by pointer
  /// address, and llama.cpp can hand back a previously freed address for a new
  /// context; forgetting the old entry stops a stale set from being re-applied
  /// to an unrelated context.
  void forgetContext(Pointer<llama_context> ctx) {
    _activeLoras.remove(ctx.address);
  }

  /// Unload a LoRA adapter.
  ///
  /// If [force] is false, decrements the reference count and only
  /// disposes when count reaches zero. If [force] is true, disposes
  /// immediately regardless of reference count.
  void unloadLora(LlamaLoraAdapter lora, {bool force = false}) {
    final path = lora.path;
    if (!_loraPool.containsKey(path)) return;

    final (adapter, refCount) = _loraPool[path]!;

    if (force || refCount <= 1) {
      // Drop it from every context's tracked set first: the adapter pointer is
      // about to become invalid and must never be handed to
      // `llama_set_adapters_lora` again.
      for (final active in _activeLoras.values) {
        active.removeWhere((e) => e.$1.path == path);
      }
      adapter.dispose();
      _loraPool.remove(path);
    } else {
      _loraPool[path] = (adapter, refCount - 1);
    }
  }

  /// Unload all LoRA adapters.
  void unloadAllLoras() {
    _activeLoras.clear();
    for (final path in _loraPool.keys.toList()) {
      final (adapter, _) = _loraPool[path]!;
      adapter.dispose();
      _loraPool.remove(path);
    }
  }

  /// Get a loaded LoRA by path.
  LlamaLoraAdapter? getLoadedLora(String path) {
    return _loraPool[path]?.$1;
  }

  /// List all loaded LoRA paths.
  List<String> get loadedLoras => _loraPool.keys.toList();

  /// Get reference count for a loaded LoRA.
  int getLoraRefCount(String path) {
    return _loraPool[path]?.$2 ?? 0;
  }

  /// Check if a LoRA is currently loaded.
  bool isLoraLoaded(String path) {
    return _loraPool.containsKey(path);
  }

  /// Dispose of all loaded LoRAs.
  void dispose() {
    unloadAllLoras();
  }
}

/// Configuration for a LoRA to be applied during inference.
class LoraConfig {
  const LoraConfig({required this.path, this.scale = 1.0});

  /// Path to the LoRA file.
  final String path;

  /// Scale factor (0.0 to 1.0+).
  final double scale;

  @override
  String toString() => 'LoraConfig($path, scale: $scale)';
}
