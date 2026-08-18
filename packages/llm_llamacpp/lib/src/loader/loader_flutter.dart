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
    // macOS: Flutter bundles every code asset as its own framework, stripping
    // the `lib` prefix and the `.dylib` extension, so `libllama.dylib` is
    // installed as `llama.framework/llama` with the install name
    // `@rpath/llama.framework/llama`. There is no `libllama.dylib` in the app
    // bundle to open by that name.
    //
    // The ggml libraries are bundled the same way, and Flutter rewrites
    // libllama's references to point at them, so dyld pulls them in on its own
    // and nothing needs pre-loading here (unlike Android, which loads its CPU
    // backends dynamically).
    return _openFirst([
      '@rpath/llama.framework/llama',
      // Non-Flutter embeddings put the plain dylib on the loader path.
      'libllama.dylib',
    ]);
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

/// Opens the first library that loads, reporting every failure if none do.
DynamicLibrary _openFirst(List<String> candidates) {
  final failures = <String>[];
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (e) {
      failures.add('  $candidate: $e');
    }
  }
  throw StateError(
    'Failed to load the llama.cpp library. Tried:\n${failures.join('\n')}',
  );
}

/// Pre-load ggml dependency libraries on Android.
///
/// On Android, shared libraries must be loaded in dependency order.
/// libllama.so depends on libggml.so which depends on libggml-base.so.
///
/// CPU Hardware Acceleration:
/// The libraries are built with GGML_BACKEND_DL=ON and GGML_CPU_ALL_VARIANTS=ON.
/// The CPU backend .so files (libggml-cpu-*.so) must be pre-loaded from Dart
/// to ensure symbol visibility when ggml_backend_load() is called later.
///
/// Load order:
/// 1. libggml-base.so (base GGML library)
/// 2. libggml.so (GGML coordinator)
/// 3. libomp.so (OpenMP runtime - required for multi-threaded CPU backends)
/// 4. libggml-cpu-*.so (CPU backend variants - all of them for symbol visibility)
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
  try {
    DynamicLibrary.open('libggml.so');
    // ignore: avoid_print
    print('[llm_llamacpp] Loaded dependency: libggml.so');
  } catch (e) {
    // ignore: avoid_print
    print('[llm_llamacpp] Failed to load libggml.so: $e');
  }

  // Load OpenMP runtime (required by CPU backends built with GGML_OPENMP=ON)
  try {
    DynamicLibrary.open('libomp.so');
    // ignore: avoid_print
    print('[llm_llamacpp] Loaded dependency: libomp.so');
  } catch (e) {
    // ignore: avoid_print
    print('[llm_llamacpp] Failed to load libomp.so: $e');
    // ignore: avoid_print
    print(
      '[llm_llamacpp] CPU backend loading will likely fail. Ensure libomp.so is bundled with the app.',
    );
  }

  // Pre-load all CPU backend variants from Dart.
  // This is critical because:
  // 1. Dart's DynamicLibrary.open() doesn't use RTLD_GLOBAL
  // 2. When ggml_backend_load() tries to load these .so files via dlopen in C++,
  //    the symbols from libggml.so/libggml-base.so aren't visible
  // 3. By pre-loading them from Dart, we ensure symbol resolution works
  //
  // The ggml_backend_load() call will still work because the libraries are
  // already in memory - dlopen will just return a handle to the existing library.
  final cpuBackends = [
    'libggml-cpu-android_armv8.0_1.so',
    'libggml-cpu-android_armv8.2_1.so',
    'libggml-cpu-android_armv8.2_2.so',
    'libggml-cpu-android_armv8.6_1.so',
    'libggml-cpu-android_armv9.0_1.so',
    'libggml-cpu-android_armv9.2_1.so',
    'libggml-cpu-android_armv9.2_2.so',
  ];

  int loadedCount = 0;
  for (final backend in cpuBackends) {
    try {
      DynamicLibrary.open(backend);
      // ignore: avoid_print
      print('[llm_llamacpp] Pre-loaded CPU backend: $backend');
      loadedCount++;
    } catch (e) {
      // Log the error for debugging
      // ignore: avoid_print
      print('[llm_llamacpp] Failed to pre-load $backend: $e');
    }
  }
  // ignore: avoid_print
  print('[llm_llamacpp] Pre-loaded $loadedCount CPU backend variant(s)');
}
