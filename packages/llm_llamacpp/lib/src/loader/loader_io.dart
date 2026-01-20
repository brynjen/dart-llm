import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Load the llama.cpp library for pure Dart (non-Flutter) applications.
DynamicLibrary loadLibrary() {
  final libraryName = _getLibraryName();

  // Try multiple locations in order of preference
  final searchPaths = _getSearchPaths(libraryName);

  // First, try to load dependency libraries (ggml) from the same directories
  _loadDependencies(searchPaths);

  for (final searchPath in searchPaths) {
    if (File(searchPath).existsSync()) {
      try {
        return DynamicLibrary.open(searchPath);
      } catch (e) {
        // Continue to next path
        print('Failed to load from $searchPath: $e');
      }
    }
  }

  // Last resort: try system library path
  try {
    return DynamicLibrary.open(libraryName);
  } catch (e) {
    throw StateError(
      'Failed to load llama.cpp library. Searched paths:\n'
      '${searchPaths.join('\n')}\n'
      'Also tried system path: $libraryName\n'
      'Error: $e',
    );
  }
}

/// Try to load dependency libraries (ggml-base, ggml-cpu, GPU backends, ggml)
///
/// Libraries are loaded in dependency order. GPU backends (CUDA, Vulkan, Metal)
/// are optional and loaded silently - if not present, CPU inference continues.
void _loadDependencies(List<String> llamaPaths) {
  // Platform-specific library lists in dependency order
  // GPU backends are optional - they fail silently if not present
  final depLibs = Platform.isLinux
      ? [
          'libggml-base.so',
          'libggml-cpu.so',
          'libggml-cuda.so', // NVIDIA GPU (optional)
          'libggml-vulkan.so', // Vulkan GPU (optional)
          'libggml.so',
        ]
      : Platform.isMacOS
      ? [
          'libggml-base.dylib',
          'libggml-cpu.dylib',
          'libggml-metal.dylib', // Apple Metal GPU (optional)
          'libggml.dylib',
        ]
      : Platform.isWindows
      ? [
          'ggml-base.dll',
          'ggml-cpu.dll',
          'ggml-cuda.dll', // NVIDIA GPU (optional)
          'ggml-vulkan.dll', // Vulkan GPU (optional)
          'ggml.dll',
        ]
      : <String>[];

  for (final depLib in depLibs) {
    for (final llamaPath in llamaPaths) {
      final depPath = path.join(path.dirname(llamaPath), depLib);
      if (File(depPath).existsSync()) {
        try {
          DynamicLibrary.open(depPath);
          break; // Successfully loaded, move to next dependency
        } catch (e) {
          // Try next path (GPU backends are optional, so continue silently)
        }
      }
    }
  }
}

String _getLibraryName() {
  if (Platform.isWindows) {
    return 'llama.dll';
  } else if (Platform.isMacOS) {
    return 'libllama.dylib';
  } else if (Platform.isLinux) {
    return 'libllama.so';
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

List<String> _getSearchPaths(String libraryName) {
  final paths = <String>[];

  // 1. Current directory
  paths.add(path.join(Directory.current.path, libraryName));

  // 2. Next to the executable
  final executableDir = path.dirname(Platform.resolvedExecutable);
  paths.add(path.join(executableDir, libraryName));

  // 3. In lib/ subdirectory next to executable
  paths.add(path.join(executableDir, 'lib', libraryName));

  // 4. Package's native libs directory (for development)
  // This handles the case where we're running from the package directory
  final scriptDir = path.dirname(Platform.script.toFilePath());
  paths.add(path.join(scriptDir, '..', 'src', libraryName));

  // 5. Package's linux/libs directory (for development with flutter plugin structure)
  paths.add(path.join(scriptDir, '..', 'linux', 'libs', libraryName));

  // 6. Also try relative to the package root
  paths.add(path.join(scriptDir, '..', '..', 'linux', 'libs', libraryName));

  // 7. Standard system paths
  if (Platform.isLinux) {
    paths.addAll([
      '/usr/local/lib/$libraryName',
      '/usr/lib/$libraryName',
      '/usr/lib/x86_64-linux-gnu/$libraryName',
      '/usr/lib/aarch64-linux-gnu/$libraryName',
    ]);
  } else if (Platform.isMacOS) {
    paths.addAll([
      '/usr/local/lib/$libraryName',
      '/opt/homebrew/lib/$libraryName',
    ]);
  }

  return paths;
}
