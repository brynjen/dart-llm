import 'dart:ffi';
import 'dart:io';

/// Load the llama.cpp library for Flutter applications.
///
/// Flutter's plugin system handles the native library loading automatically
/// when using an FFI plugin structure. The library is bundled with the app
/// and accessible via the standard plugin mechanism.
DynamicLibrary loadLibrary() {
  if (Platform.isAndroid) {
    // Android: Pre-load ggml dependencies before loading libllama.so
    // These libraries must be loaded in dependency order
    _loadAndroidDependencies();
    try {
      final lib = DynamicLibrary.open('libllama.so');
      // ignore: avoid_print
      print('[llm_llamacpp] Successfully loaded libllama.so');
      return lib;
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ERROR loading libllama.so: $e');
      rethrow;
    }
  } else if (Platform.isIOS) {
    // iOS: Framework is linked statically or via xcframework
    return DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    // macOS: Dylib is bundled in the app
    return DynamicLibrary.open('libllama.dylib');
  } else if (Platform.isWindows) {
    // Windows: DLL is bundled with the app
    return DynamicLibrary.open('llama.dll');
  } else if (Platform.isLinux) {
    // Linux: Shared library is bundled with the app
    return DynamicLibrary.open('libllama.so');
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

/// Pre-load ggml dependency libraries on Android.
///
/// On Android, shared libraries must be loaded in dependency order.
/// libllama.so depends on libggml.so which depends on libggml-base.so.
///
/// CPU Hardware Acceleration:
/// The libraries are built with GGML_BACKEND_DL=ON and GGML_CPU_ALL_VARIANTS=ON.
/// This means libggml.so will dynamically load the optimal CPU backend variant
/// at runtime based on device capabilities (ARM dotprod, SVE, SME2, etc.).
///
/// Load order:
/// 1. libggml-base.so (base GGML library)
/// 2. libggml.so (GGML coordinator - dynamically loads CPU backends)
void _loadAndroidDependencies() {
  // Load base library first
  try {
    DynamicLibrary.open('libggml-base.so');
    // ignore: avoid_print
    print('[llm_llamacpp] Loaded dependency: libggml-base.so');
  } catch (e) {
    // ignore: avoid_print
    print('[llm_llamacpp] Failed to load libggml-base.so: $e');
  }

  // Load the GGML coordinator library
  // With GGML_BACKEND_DL=ON, this will dynamically load the optimal CPU backend
  try {
    DynamicLibrary.open('libggml.so');
    // ignore: avoid_print
    print('[llm_llamacpp] Loaded dependency: libggml.so');
  } catch (e) {
    // ignore: avoid_print
    print('[llm_llamacpp] Failed to load libggml.so: $e');
  }
}
