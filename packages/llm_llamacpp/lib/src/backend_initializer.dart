import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/loader/native_library_path.dart';

/// Helper class for initializing the llama.cpp backend.
///
/// This consolidates the backend initialization logic that was previously
/// duplicated across multiple files. It handles dynamic backend loading
/// which is required when GGML_BACKEND_DL=ON (e.g., on Android where
/// backends are loaded as separate .so files).
class BackendInitializer {
  BackendInitializer._();

  /// Tracks whether backends have been initialized in this process.
  /// Native libraries are shared across isolates, so we only need to
  /// load backends once. Loading them multiple times can cause crashes.
  static bool _backendsInitialized = false;

  /// Initializes the llama.cpp backend with dynamic backend loading support.
  ///
  /// This method:
  /// 1. Loads the llama library
  /// 2. Creates LlamaBindings
  /// 3. Attempts to load all backends dynamically (if available) - only once per process
  /// 4. Initializes the backend
  ///
  /// Returns a tuple of (DynamicLibrary, LlamaBindings).
  static (ffi.DynamicLibrary, LlamaBindings) initializeBackend() {
    final lib = loadLlamaLibrary();
    final bindings = LlamaBindings(lib);

    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files
    //
    // IMPORTANT: Only load backends once per process!
    // Native library state is shared across Dart isolates. If we load backends
    // multiple times (e.g., once in main isolate, once in inference isolate),
    // it can cause corruption and crashes.
    if (!_backendsInitialized) {
      // ignore: avoid_print
      print('[llm_llamacpp] Initializing backends (first time)...');
      loadBackends(lib);
      _backendsInitialized = true;
    } else {
      // ignore: avoid_print
      print('[llm_llamacpp] Backends already initialized, skipping...');
    }

    bindings.llama_backend_init();

    return (lib, bindings);
  }

  /// Initializes the llama.cpp backend in an isolate (skips all backend loading).
  ///
  /// This should be used in inference isolates. The native backends are already
  /// loaded into the process's native memory space by the main isolate - they're
  /// shared across isolates. Trying to load them again causes corruption/crashes.
  ///
  /// This method:
  /// 1. Opens libllama.so directly (skips _loadAndroidDependencies which would preload backends)
  /// 2. Creates LlamaBindings
  /// 3. Initializes the backend (but does NOT reload backend .so files)
  ///
  /// Returns a tuple of (DynamicLibrary, LlamaBindings).
  static (ffi.DynamicLibrary, LlamaBindings) initializeBackendForIsolate() {
    // ignore: avoid_print
    print(
      '[llm_llamacpp] Initializing backend for isolate (minimal loading)...',
    );

    // On Android, don't call loadLlamaLibrary() because it calls _loadAndroidDependencies()
    // which would try to DynamicLibrary.open() all the CPU backends again.
    // Just open libllama.so directly - all dependencies are already loaded in native memory.
    ffi.DynamicLibrary lib;
    if (Platform.isAndroid) {
      lib = ffi.DynamicLibrary.open('libllama.so');
    } else {
      // On other platforms, use the standard loader
      lib = loadLlamaLibrary();
    }

    final bindings = LlamaBindings(lib);

    // Skip backend loading - backends are already loaded and registered in native memory
    // by the main isolate. Just call llama_backend_init() which is safe to call multiple times.
    bindings.llama_backend_init();

    return (lib, bindings);
  }

  /// Initializes backend loading on an already-loaded library and bindings.
  ///
  /// This is useful when you already have a library and bindings instance
  /// and just need to perform the backend loading step.
  ///
  /// On Android, this uses dladdr to get the native library directory path
  /// and passes it to ggml_backend_load_all_from_path(). This is required
  /// because ggml_backend_load_all() tries to access /proc/self/exe which
  /// is blocked by SELinux on Android.
  ///
  /// Returns true if backends were loaded successfully, false otherwise.
  static bool loadBackends(ffi.DynamicLibrary lib) {
    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files

    // On Android, we must use ggml_backend_load_all_from_path with the actual
    // native library directory. Using ggml_backend_load_all() without a path
    // causes SELinux "avc: denied" errors because it tries to read /proc/self/exe.
    if (Platform.isAndroid) {
      return _loadBackendsAndroid(lib);
    }

    // On other platforms, try ggml_backend_load_all (simpler, no path needed)
    try {
      final ggmlBackendLoadAll = lib
          .lookupFunction<ffi.Void Function(), void Function()>(
            'ggml_backend_load_all',
          );
      ggmlBackendLoadAll();
      return true;
    } catch (e) {
      // Function not found - try path-based version
    }

    // Try ggml_backend_load_all_from_path with null (uses default paths)
    try {
      final ggmlBackendLoadAllFromPath = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Char>),
            void Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load_all_from_path');
      ggmlBackendLoadAllFromPath(ffi.Pointer.fromAddress(0));
      return true;
    } catch (e2) {
      // ignore: avoid_print
      print('[llm_llamacpp] Warning: Could not load backends dynamically: $e2');
      // ignore: avoid_print
      print(
        '[llm_llamacpp] This may cause model loading to fail if backends are not statically linked',
      );
      return false;
    }
  }

  /// Load backends on Android using the native library directory path.
  ///
  /// Android requires passing the actual native library directory to
  /// ggml_backend_load_all_from_path() because:
  /// 1. ggml_backend_load_all() tries to read /proc/self/exe
  /// 2. SELinux blocks untrusted apps from reading the root filesystem
  /// 3. This causes "no backends are loaded" errors
  ///
  /// If ggml_backend_load_all_from_path() doesn't work (which can happen due to
  /// std::filesystem issues on some Android versions), we fall back to manually
  /// loading each CPU backend .so file using ggml_backend_load().
  static bool _loadBackendsAndroid(ffi.DynamicLibrary lib) {
    // Get the native library directory using dladdr
    final nativeLibDir = getNativeLibraryDirectory(lib);

    if (nativeLibDir == null) {
      // ignore: avoid_print
      print(
        '[llm_llamacpp] WARNING: Could not determine native library directory on Android',
      );
      // ignore: avoid_print
      print(
        '[llm_llamacpp] Falling back to ggml_backend_load_all() which may fail due to SELinux',
      );

      // Try anyway - it might work on some devices
      try {
        final ggmlBackendLoadAll = lib
            .lookupFunction<ffi.Void Function(), void Function()>(
              'ggml_backend_load_all',
            );
        ggmlBackendLoadAll();
        // ignore: avoid_print
        print(
          '[llm_llamacpp] Called ggml_backend_load_all() - backends might be loaded',
        );
        return true;
      } catch (e) {
        // ignore: avoid_print
        print('[llm_llamacpp] ERROR: ggml_backend_load_all failed: $e');
        return false;
      }
    }

    // Try ggml_backend_load_all_from_path first
    try {
      final ggmlBackendLoadAllFromPath = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Char>),
            void Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load_all_from_path');

      // Convert the path to a native string
      final pathPtr = nativeLibDir.toNativeUtf8();
      try {
        ggmlBackendLoadAllFromPath(pathPtr.cast<ffi.Char>());
        // ignore: avoid_print
        print(
          '[llm_llamacpp] Called ggml_backend_load_all_from_path("$nativeLibDir")',
        );
      } finally {
        calloc.free(pathPtr);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ggml_backend_load_all_from_path failed: $e');
    }

    // ggml_backend_load_all_from_path may silently fail on Android due to
    // std::filesystem issues. Fall back to manually loading each backend.
    return _loadBackendsManually(lib, nativeLibDir);
  }

  /// Manually load backend .so files from the given directory.
  ///
  /// This is a fallback for when ggml_backend_load_all_from_path doesn't work
  /// (which can happen on Android due to std::filesystem issues).
  static bool _loadBackendsManually(
    ffi.DynamicLibrary lib,
    String nativeLibDir,
  ) {
    // ignore: avoid_print
    print(
      '[llm_llamacpp] Attempting manual backend loading from: $nativeLibDir',
    );

    // Get the ggml_backend_load function
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) ggmlBackendLoad;
    try {
      ggmlBackendLoad = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load');
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ERROR: ggml_backend_load not found: $e');
      return false;
    }

    // List the directory to find CPU backend .so files
    final dir = Directory(nativeLibDir);
    if (!dir.existsSync()) {
      // ignore: avoid_print
      print(
        '[llm_llamacpp] ERROR: Native library directory does not exist: $nativeLibDir',
      );
      return false;
    }

    int loadedCount = 0;

    try {
      final files = dir.listSync();
      // ignore: avoid_print
      print(
        '[llm_llamacpp] Found ${files.length} files in native lib directory',
      );

      for (final entity in files) {
        if (entity is File) {
          final filename = entity.uri.pathSegments.last;
          // Look for CPU backend files: libggml-cpu-*.so
          if (filename.startsWith('libggml-cpu-') && filename.endsWith('.so')) {
            final fullPath = entity.path;
            // ignore: avoid_print
            print('[llm_llamacpp] Loading backend: $filename');

            final pathPtr = fullPath.toNativeUtf8();
            try {
              final result = ggmlBackendLoad(pathPtr.cast<ffi.Char>());
              if (result.address != 0) {
                // ignore: avoid_print
                print('[llm_llamacpp] Successfully loaded: $filename');
                loadedCount++;
              } else {
                // ignore: avoid_print
                print(
                  '[llm_llamacpp] Failed to load: $filename (returned null)',
                );
              }
            } finally {
              calloc.free(pathPtr);
            }
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ERROR listing directory: $e');
      return false;
    }

    // ignore: avoid_print
    print('[llm_llamacpp] Manually loaded $loadedCount CPU backend(s)');
    return loadedCount > 0;
  }
}
