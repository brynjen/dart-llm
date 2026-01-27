import 'dart:io';

/// Configuration for integration tests.
///
/// Models can be specified via environment variables:
/// - LLAMA_TEST_MODEL: Path to a standard text model (GGUF)
/// - LLAMA_TEST_VISION_MODEL: Path to a vision model (GGUF)
/// - LLAMA_TEST_SMALL_MODEL: Path to a small/fast model for quick tests
/// - LLAMA_TEST_GPU_LAYERS: Number of GPU layers to use (default: 0)
///
/// Or place models in the test/models/ directory:
/// - test/models/text.gguf
/// - test/models/vision.gguf
/// - test/models/small.gguf
class TestConfig {
  TestConfig._();

  static final TestConfig instance = TestConfig._();

  /// Get the test model directory
  String get modelDir {
    final scriptDir = Platform.script.toFilePath();
    final packageDir = scriptDir.contains('test/')
        ? scriptDir.substring(0, scriptDir.indexOf('test/'))
        : Directory.current.path;
    return '$packageDir/test/models';
  }

  /// Path to a standard text model for testing
  String? get textModelPath {
    // Check environment variable first
    final envPath = Platform.environment['LLAMA_TEST_MODEL'];
    if (envPath != null && File(envPath).existsSync()) {
      return envPath;
    }

    // Check test/models directory
    final localPath = '$modelDir/text.gguf';
    if (File(localPath).existsSync()) {
      return localPath;
    }

    // Check common locations
    final commonPaths = ['/tmp/qwen2.5-0.5b-q4.gguf', '/tmp/test-model.gguf'];
    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return null;
  }

  /// Path to a vision model for testing
  String? get visionModelPath {
    final envPath = Platform.environment['LLAMA_TEST_VISION_MODEL'];
    if (envPath != null && File(envPath).existsSync()) {
      return envPath;
    }

    final localPath = '$modelDir/vision.gguf';
    if (File(localPath).existsSync()) {
      return localPath;
    }

    // Check common locations
    final commonPaths = ['/tmp/qwen3-vl-8b-q4km.gguf', '/tmp/qwen3-vl.gguf'];
    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return null;
  }

  /// Path to a small model for quick tests
  String? get smallModelPath {
    final envPath = Platform.environment['LLAMA_TEST_SMALL_MODEL'];
    if (envPath != null && File(envPath).existsSync()) {
      return envPath;
    }

    final localPath = '$modelDir/small.gguf';
    if (File(localPath).existsSync()) {
      return localPath;
    }

    // Fall back to text model
    return textModelPath;
  }

  /// Number of GPU layers to use
  int get gpuLayers {
    final envLayers = Platform.environment['LLAMA_TEST_GPU_LAYERS'];
    if (envLayers != null) {
      return int.tryParse(envLayers) ?? 0;
    }
    return 0;
  }

  /// Whether to use GPU acceleration
  bool get useGpu => gpuLayers > 0;

  /// Check if any model is available for testing
  bool get hasAnyModel =>
      textModelPath != null ||
      visionModelPath != null ||
      smallModelPath != null;

  /// Print configuration summary
  void printConfig() {
    print('╔════════════════════════════════════════════════════════════╗');
    print('║              llm_llamacpp Integration Tests                 ║');
    print('╠════════════════════════════════════════════════════════════╣');
    print('║ Text Model:   ${_formatPath(textModelPath)}');
    print('║ Vision Model: ${_formatPath(visionModelPath)}');
    print('║ Small Model:  ${_formatPath(smallModelPath)}');
    print('║ GPU Layers:   $gpuLayers');
    print('╚════════════════════════════════════════════════════════════╝');
  }

  String _formatPath(String? path) {
    if (path == null) return '❌ Not found';
    final file = File(path);
    if (!file.existsSync()) return '❌ Not found';
    final size = file.lengthSync();
    final sizeStr = size > 1024 * 1024 * 1024
        ? '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)}GB'
        : '${(size / 1024 / 1024).toStringAsFixed(0)}MB';
    final name = path.split('/').last;
    return '✅ $name ($sizeStr)';
  }
}

/// Helper to skip tests when model is not available
void skipIfNoModel(String? modelPath, String modelType) {
  if (modelPath == null || !File(modelPath).existsSync()) {
    throw TestSkippedException(
      'No $modelType model available. '
      'Set LLAMA_TEST_MODEL environment variable or place model in test/models/',
    );
  }
}

/// Exception to skip a test
class TestSkippedException implements Exception {
  final String message;
  TestSkippedException(this.message);
  @override
  String toString() => message;
}
