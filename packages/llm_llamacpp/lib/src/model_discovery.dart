import 'dart:io';

import 'package:llm_llamacpp/src/gguf_metadata.dart';
import 'package:llm_llamacpp/src/model_info.dart';

/// Discovers GGUF models in directories and reads their metadata.
class LlamaCppModelDiscovery {
  LlamaCppModelDiscovery({Set<String>? loadedModelPaths})
    : _loadedModelPaths = loadedModelPaths ?? {};

  /// Set of currently loaded model paths (for isLoaded flag).
  final Set<String> _loadedModelPaths;

  /// Update the set of loaded model paths.
  void updateLoadedPaths(Set<String> paths) {
    _loadedModelPaths.clear();
    _loadedModelPaths.addAll(paths);
  }

  /// Discover GGUF models in a directory.
  ///
  /// [directory] - Directory to scan for GGUF files.
  /// [recursive] - Whether to scan subdirectories.
  /// [readMetadata] - Whether to read GGUF metadata (slower but more info).
  Future<List<ModelInfo>> discoverModels(
    String directory, {
    bool recursive = false,
    bool readMetadata = true,
  }) async {
    final dir = Directory(directory);
    // ignore: avoid_slow_async_io
    if (!await dir.exists()) {
      return [];
    }

    final models = <ModelInfo>[];
    final entities = recursive ? dir.listSync(recursive: true) : dir.listSync();

    for (final entity in entities) {
      if (entity is File && _isGgufFile(entity.path)) {
        try {
          final info = await getModelInfo(
            entity.path,
            readMetadata: readMetadata,
          );
          models.add(info);
        } catch (e) {
          // Skip files that can't be read
        }
      }
    }

    return models;
  }

  /// Get information about a specific model file.
  ///
  /// [path] - Path to the GGUF file.
  /// [readMetadata] - Whether to read GGUF metadata.
  Future<ModelInfo> getModelInfo(
    String path, {
    bool readMetadata = true,
  }) async {
    final file = File(path);
    // ignore: avoid_slow_async_io
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }

    final name = _extractModelName(path);
    final fileSize = await file.length();
    final isLoaded = _loadedModelPaths.contains(path);

    GgufMetadata? metadata;
    if (readMetadata) {
      try {
        metadata = await GgufMetadata.fromFile(path);
      } catch (e) {
        // Metadata reading failed, continue without it
      }
    }

    return ModelInfo(
      path: path,
      name: name,
      fileSize: fileSize,
      metadata: metadata,
      isLoaded: isLoaded,
    );
  }

  /// Check if a file is a valid GGUF model.
  bool isValidModel(String path) {
    return GgufMetadata.isValidGguf(path);
  }

  /// Read metadata from a GGUF file without loading the model.
  Future<GgufMetadata> readMetadata(String path) {
    return GgufMetadata.fromFile(path);
  }

  /// Discover models from common locations.
  ///
  /// Searches:
  /// - ~/.cache/llm_llamacpp/models/
  /// - ~/.ollama/models/blobs/ (Ollama models)
  /// - /usr/share/gguf-models/ (system-wide)
  Future<List<ModelInfo>> discoverCommonLocations({
    bool readMetadata = true,
  }) async {
    final home = Platform.environment['HOME'] ?? '';
    final locations = [
      '$home/.cache/llm_llamacpp/models',
      '$home/.ollama/models/blobs',
      '/usr/share/gguf-models',
      '/usr/local/share/gguf-models',
    ];

    final models = <ModelInfo>[];
    for (final location in locations) {
      // ignore: avoid_slow_async_io
      if (await Directory(location).exists()) {
        models.addAll(
          await discoverModels(location, readMetadata: readMetadata),
        );
      }
    }

    return models;
  }

  bool _isGgufFile(String path) {
    final lower = path.toLowerCase();
    if (!lower.endsWith('.gguf')) {
      // Also check Ollama blob format (sha256-...)
      if (!path.contains('sha256-')) return false;
    }
    return GgufMetadata.isValidGguf(path);
  }

  String _extractModelName(String path) {
    final filename = path.split(Platform.pathSeparator).last;

    // Handle Ollama blob format
    if (filename.startsWith('sha256-')) {
      return 'ollama-${filename.substring(7, 15)}...';
    }

    // Remove .gguf extension
    if (filename.toLowerCase().endsWith('.gguf')) {
      return filename.substring(0, filename.length - 5);
    }

    return filename;
  }
}
