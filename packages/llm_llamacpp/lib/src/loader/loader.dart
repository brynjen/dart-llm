import 'dart:ffi';

import 'loader_stub.dart'
    if (dart.library.ui) 'loader_flutter.dart'
    if (dart.library.ffi) 'loader_io.dart';

/// Loads the llama.cpp native library.
///
/// This uses conditional imports to load the library from the appropriate
/// location depending on the platform:
/// - Flutter: Uses plugin path resolution
/// - Pure Dart: Loads from bundled paths or system paths
DynamicLibrary loadLlamaLibrary() => loadLibrary();
