import 'dart:ffi';

/// Stub implementation for platforms that don't support FFI.
DynamicLibrary loadLibrary() {
  throw UnsupportedError(
    'Cannot load llama.cpp library: FFI is not available on this platform',
  );
}

