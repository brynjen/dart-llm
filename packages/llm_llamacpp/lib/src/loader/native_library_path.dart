import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Dl_info structure used by dladdr to return information about a symbol.
///
/// On Linux/Android, this struct has the following layout:
/// ```c
/// typedef struct {
///     const char *dli_fname;  // Pathname of shared object containing address
///     void       *dli_fbase;  // Base address at which shared object is loaded
///     const char *dli_sname;  // Name of nearest symbol with address lower than addr
///     void       *dli_saddr;  // Address of nearest symbol
/// } Dl_info;
/// ```
final class DlInfo extends ffi.Struct {
  // ignore: non_constant_identifier_names
  external ffi.Pointer<ffi.Char> dli_fname;
  // ignore: non_constant_identifier_names
  external ffi.Pointer<ffi.Void> dli_fbase;
  // ignore: non_constant_identifier_names
  external ffi.Pointer<ffi.Char> dli_sname;
  // ignore: non_constant_identifier_names
  external ffi.Pointer<ffi.Void> dli_saddr;
}

/// Typedef for dladdr function signature.
typedef DladdrNative =
    ffi.Int Function(ffi.Pointer<ffi.Void> addr, ffi.Pointer<DlInfo> info);
typedef DladdrDart =
    int Function(ffi.Pointer<ffi.Void> addr, ffi.Pointer<DlInfo> info);

/// Gets the directory containing the native library on Android using dladdr.
///
/// This function uses the POSIX dladdr() to get the path of the loaded library,
/// which is needed on Android to pass to ggml_backend_load_all_from_path().
///
/// Returns null on non-Android platforms or if the path cannot be determined.
String? getNativeLibraryDirectory(ffi.DynamicLibrary lib) {
  if (!Platform.isAndroid) {
    return null;
  }

  try {
    // Load libc to access dladdr
    final libc = ffi.DynamicLibrary.open('libc.so');

    // Get dladdr function
    final dladdr = libc.lookupFunction<DladdrNative, DladdrDart>('dladdr');

    // Get a symbol address from the loaded library to use with dladdr
    // We use llama_backend_init as it's always present
    final symbolAddr = lib.lookup<ffi.Void>('llama_backend_init');

    // Allocate Dl_info structure
    final dlInfoPtr = calloc<DlInfo>();

    try {
      // Call dladdr
      final result = dladdr(symbolAddr, dlInfoPtr);

      if (result != 0 && dlInfoPtr.ref.dli_fname.address != 0) {
        // Get the full path to the library
        final fullPath = dlInfoPtr.ref.dli_fname.cast<Utf8>().toDartString();

        // Check if the library is loaded from inside an APK (not extracted)
        // This happens when android:extractNativeLibs="false" (the default)
        // The path will contain "base.apk!" like:
        // /data/app/.../base.apk!/lib/arm64-v8a
        if (fullPath.contains('.apk!')) {
          // ignore: avoid_print
          print(
            '[llm_llamacpp] ERROR: Native libraries are loaded from APK, not extracted to filesystem.',
          );
          // ignore: avoid_print
          print('[llm_llamacpp] Library path: $fullPath');
          // ignore: avoid_print
          print(
            '[llm_llamacpp] To fix this, add android:extractNativeLibs="true" to your AndroidManifest.xml <application> element.',
          );
          // ignore: avoid_print
          print(
            '[llm_llamacpp] This is required for ggml_backend_load_all_from_path() to find backend .so files.',
          );
          return null;
        }

        // Extract the directory part
        final lastSlash = fullPath.lastIndexOf('/');
        if (lastSlash > 0) {
          final directory = fullPath.substring(0, lastSlash);
          // ignore: avoid_print
          print('[llm_llamacpp] Native library directory: $directory');
          return directory;
        }
      }
    } finally {
      calloc.free(dlInfoPtr);
    }
  } catch (e) {
    // ignore: avoid_print
    print('[llm_llamacpp] Error getting native library directory: $e');
  }

  return null;
}
