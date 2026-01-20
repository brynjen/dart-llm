import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// ignore_for_file: constant_identifier_names

/// Quantization types supported by llama.cpp
enum QuantizationType {
  /// 32-bit float (no quantization, largest)
  f32('f32', 'F32'),

  /// 16-bit float
  f16('f16', 'F16'),

  /// 16-bit brain float
  bf16('bf16', 'BF16'),

  /// 8-bit quantization
  q8_0('q8_0', 'Q8_0'),

  /// 4-bit quantization (medium quality, good balance)
  q4_k_m('q4_k_m', 'Q4_K_M'),

  /// 4-bit quantization (small)
  q4_k_s('q4_k_s', 'Q4_K_S'),

  /// 5-bit quantization (medium)
  q5_k_m('q5_k_m', 'Q5_K_M'),

  /// 5-bit quantization (small)
  q5_k_s('q5_k_s', 'Q5_K_S'),

  /// 6-bit quantization
  q6_k('q6_k', 'Q6_K'),

  /// 3-bit quantization (medium)
  q3_k_m('q3_k_m', 'Q3_K_M'),

  /// 3-bit quantization (large)
  q3_k_l('q3_k_l', 'Q3_K_L'),

  /// 2-bit quantization (very small, lower quality)
  q2_k('q2_k', 'Q2_K'),

  /// IQ4 (imatrix-based 4-bit)
  iq4_xs('iq4_xs', 'IQ4_XS'),

  /// IQ3 (imatrix-based 3-bit)
  iq3_m('iq3_m', 'IQ3_M'),

  /// IQ2 (imatrix-based 2-bit, smallest)
  iq2_xxs('iq2_xxs', 'IQ2_XXS');

  const QuantizationType(this.cliName, this.displayName);

  /// Name used in CLI commands
  final String cliName;

  /// Human-readable display name
  final String displayName;

  /// Approximate compression ratio compared to F16
  double get compressionRatio {
    switch (this) {
      case QuantizationType.f32:
        return 0.5;
      case QuantizationType.f16:
      case QuantizationType.bf16:
        return 1.0;
      case QuantizationType.q8_0:
        return 2.0;
      case QuantizationType.q6_k:
        return 2.7;
      case QuantizationType.q5_k_m:
      case QuantizationType.q5_k_s:
        return 3.2;
      case QuantizationType.q4_k_m:
      case QuantizationType.q4_k_s:
        return 4.0;
      case QuantizationType.q3_k_m:
      case QuantizationType.q3_k_l:
        return 5.3;
      case QuantizationType.q2_k:
        return 8.0;
      case QuantizationType.iq4_xs:
        return 4.2;
      case QuantizationType.iq3_m:
        return 5.5;
      case QuantizationType.iq2_xxs:
        return 10.0;
    }
  }
}

/// Progress information for model conversion.
class ConversionProgress {
  ConversionProgress({
    required this.stage,
    required this.message,
    this.progress,
    this.error,
  });

  /// Current conversion stage.
  final ConversionStage stage;

  /// Status message.
  final String message;

  /// Progress (0.0 to 1.0) if available.
  final double? progress;

  /// Error message if failed.
  final String? error;

  bool get isError => error != null;
  bool get isComplete => stage == ConversionStage.complete;
}

/// Conversion stages.
enum ConversionStage {
  /// Checking requirements
  checking,

  /// Downloading model files
  downloading,

  /// Converting to GGUF
  converting,

  /// Quantizing model
  quantizing,

  /// Cleaning up
  cleanup,

  /// Conversion complete
  complete,

  /// Conversion failed
  failed,
}

/// Model file information from HuggingFace.
class HfModelFile {
  HfModelFile({required this.filename, required this.size, this.sha256});

  final String filename;
  final int size;
  final String? sha256;

  factory HfModelFile.fromJson(Map<String, dynamic> json) {
    // HuggingFace API uses 'path' for filename, 'rfilename' was the old format
    final filename = json['path'] as String? ?? json['rfilename'] as String;
    return HfModelFile(
      filename: filename,
      size: (json['size'] as int?) ?? 0,
      sha256: json['oid'] as String?,
    );
  }
}

/// Converts HuggingFace models (safetensors) to GGUF format.
///
/// This requires:
/// - Python 3.8+
/// - llama.cpp repository (for conversion scripts)
/// - transformers, torch, safetensors packages
///
/// Example:
/// ```dart
/// final converter = ModelConverter(
///   llamaCppPath: '/path/to/llama.cpp',
/// );
///
/// await for (final progress in converter.convertFromHuggingFace(
///   repoId: 'Qwen/Qwen2.5-0.5B-Instruct',
///   outputPath: '/path/to/output/qwen2.5-0.5b.gguf',
///   quantization: QuantizationType.q4_k_m,
/// )) {
///   print('${progress.stage}: ${progress.message}');
/// }
/// ```
class ModelConverter {
  ModelConverter({
    this.llamaCppPath,
    this.pythonPath = 'python3',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Path to llama.cpp repository (contains convert scripts).
  /// If null, will try to find it in common locations.
  final String? llamaCppPath;

  /// Path to Python executable.
  final String pythonPath;

  final http.Client _httpClient;

  /// Check if conversion requirements are met.
  Future<(bool, List<String>)> checkRequirements() async {
    final missing = <String>[];

    // Check Python
    try {
      final result = await Process.run(pythonPath, ['--version']);
      if (result.exitCode != 0) {
        missing.add('Python 3.8+ not found');
      }
    } catch (e) {
      missing.add('Python 3.8+ not found');
    }

    // Check for convert script
    final convertScript = await _findConvertScript();
    if (convertScript == null) {
      missing.add('llama.cpp convert script not found');
    }

    // Check Python packages
    final packages = ['transformers', 'torch', 'safetensors', 'sentencepiece'];
    for (final pkg in packages) {
      try {
        final result = await Process.run(pythonPath, ['-c', 'import $pkg']);
        if (result.exitCode != 0) {
          missing.add('Python package: $pkg');
        }
      } catch (e) {
        missing.add('Python package: $pkg');
      }
    }

    return (missing.isEmpty, missing);
  }

  /// List files in a HuggingFace repository.
  Future<List<HfModelFile>> listRepoFiles(
    String repoId, {
    String revision = 'main',
  }) async {
    final url = 'https://huggingface.co/api/models/$repoId/tree/$revision';
    final response = await _httpClient.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to list repo files: HTTP ${response.statusCode}');
    }

    final List<dynamic> files = json.decode(response.body);
    return files
        .where((f) => f['type'] == 'file')
        .map((f) => HfModelFile.fromJson(f))
        .toList();
  }

  /// Check if a HuggingFace repo has GGUF files.
  Future<List<String>> findGgufFiles(
    String repoId, {
    String revision = 'main',
  }) async {
    final files = await listRepoFiles(repoId, revision: revision);
    return files
        .where((f) => f.filename.toLowerCase().endsWith('.gguf'))
        .map((f) => f.filename)
        .toList();
  }

  /// Check if a HuggingFace repo has safetensors files.
  Future<bool> hasSafetensors(String repoId, {String revision = 'main'}) async {
    final files = await listRepoFiles(repoId, revision: revision);
    return files.any((f) => f.filename.endsWith('.safetensors'));
  }

  /// Convert a HuggingFace model to GGUF format.
  ///
  /// [repoId] - HuggingFace repository ID (e.g., 'Qwen/Qwen2.5-0.5B-Instruct').
  /// [outputPath] - Path for the output GGUF file.
  /// [quantization] - Quantization type (null for F16).
  /// [revision] - Git revision (branch, tag, commit).
  /// [cacheDir] - Directory to cache downloaded files.
  Stream<ConversionProgress> convertFromHuggingFace({
    required String repoId,
    required String outputPath,
    QuantizationType? quantization,
    String revision = 'main',
    String? cacheDir,
  }) async* {
    // Check requirements
    yield ConversionProgress(
      stage: ConversionStage.checking,
      message: 'Checking requirements...',
    );

    final (reqMet, missing) = await checkRequirements();
    if (!reqMet) {
      yield ConversionProgress(
        stage: ConversionStage.failed,
        message: 'Missing requirements',
        error:
            'Missing: ${missing.join(", ")}\n\n'
            'Install with:\n'
            '  pip install transformers torch safetensors sentencepiece',
      );
      return;
    }

    // Check if GGUF already exists
    final ggufFiles = await findGgufFiles(repoId, revision: revision);
    if (ggufFiles.isNotEmpty) {
      yield ConversionProgress(
        stage: ConversionStage.checking,
        message:
            'Note: GGUF files already exist in repo: ${ggufFiles.join(", ")}',
      );
    }

    // Set up cache directory
    final workDir =
        cacheDir ??
        '${Platform.environment['HOME']}/.cache/llm_llamacpp/convert';
    final modelCacheDir = '$workDir/${repoId.replaceAll("/", "_")}';
    await Directory(modelCacheDir).create(recursive: true);

    // Download model files
    yield ConversionProgress(
      stage: ConversionStage.downloading,
      message: 'Downloading model files...',
    );

    try {
      await _downloadModelFiles(repoId, modelCacheDir, revision);
    } catch (e) {
      yield ConversionProgress(
        stage: ConversionStage.failed,
        message: 'Download failed',
        error: e.toString(),
      );
      return;
    }

    // Find convert script
    final convertScript = await _findConvertScript();
    if (convertScript == null) {
      yield ConversionProgress(
        stage: ConversionStage.failed,
        message: 'Convert script not found',
        error: 'Could not find convert_hf_to_gguf.py in llama.cpp',
      );
      return;
    }

    // Create output directory
    await Directory(File(outputPath).parent.path).create(recursive: true);

    // Determine output path for conversion (before quantization)
    final baseOutputPath = quantization != null
        ? outputPath.replaceAll('.gguf', '-f16.gguf')
        : outputPath;

    // Convert to GGUF
    yield ConversionProgress(
      stage: ConversionStage.converting,
      message: 'Converting to GGUF format...',
    );

    try {
      final convertResult = await Process.run(pythonPath, [
        convertScript,
        modelCacheDir,
        '--outfile',
        baseOutputPath,
        '--outtype',
        'f16',
      ], workingDirectory: File(convertScript).parent.path);

      if (convertResult.exitCode != 0) {
        yield ConversionProgress(
          stage: ConversionStage.failed,
          message: 'Conversion failed',
          error: convertResult.stderr.toString(),
        );
        return;
      }
    } catch (e) {
      yield ConversionProgress(
        stage: ConversionStage.failed,
        message: 'Conversion failed',
        error: e.toString(),
      );
      return;
    }

    // Quantize if requested
    if (quantization != null) {
      yield ConversionProgress(
        stage: ConversionStage.quantizing,
        message: 'Quantizing to ${quantization.displayName}...',
      );

      try {
        final quantizeScript = await _findQuantizeScript();
        if (quantizeScript == null) {
          yield ConversionProgress(
            stage: ConversionStage.failed,
            message: 'Quantize tool not found',
            error: 'Could not find llama-quantize in llama.cpp',
          );
          return;
        }

        final quantizeResult = await Process.run(quantizeScript, [
          baseOutputPath,
          outputPath,
          quantization.cliName,
        ]);

        if (quantizeResult.exitCode != 0) {
          yield ConversionProgress(
            stage: ConversionStage.failed,
            message: 'Quantization failed',
            error: quantizeResult.stderr.toString(),
          );
          return;
        }

        // Clean up F16 intermediate file
        await File(baseOutputPath).delete();
      } catch (e) {
        yield ConversionProgress(
          stage: ConversionStage.failed,
          message: 'Quantization failed',
          error: e.toString(),
        );
        return;
      }
    }

    // Clean up cache (optional)
    yield ConversionProgress(
      stage: ConversionStage.cleanup,
      message: 'Cleaning up...',
    );

    yield ConversionProgress(
      stage: ConversionStage.complete,
      message: 'Conversion complete: $outputPath',
    );
  }

  /// Download required model files from HuggingFace.
  Future<void> _downloadModelFiles(
    String repoId,
    String outputDir,
    String revision,
  ) async {
    final files = await listRepoFiles(repoId, revision: revision);

    // Files we need for conversion
    final requiredPatterns = [
      RegExp(r'.*\.safetensors$'),
      RegExp(r'config\.json$'),
      RegExp(r'tokenizer\.json$'),
      RegExp(r'tokenizer_config\.json$'),
      RegExp(r'tokenizer\.model$'),
      RegExp(r'special_tokens_map\.json$'),
      RegExp(r'generation_config\.json$'),
    ];

    final filesToDownload = files.where((f) {
      return requiredPatterns.any((p) => p.hasMatch(f.filename));
    }).toList();

    for (final file in filesToDownload) {
      final outputPath = '$outputDir/${file.filename}';

      // Skip if already downloaded
      // ignore: avoid_slow_async_io
      if (await File(outputPath).exists()) {
        final existingSize = await File(outputPath).length();
        if (existingSize == file.size) {
          continue;
        }
      }

      // Create subdirectories if needed
      await Directory(File(outputPath).parent.path).create(recursive: true);

      // Download
      final url =
          'https://huggingface.co/$repoId/resolve/$revision/${file.filename}';
      final response = await _httpClient.send(
        http.Request('GET', Uri.parse(url)),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to download ${file.filename}');
      }

      final sink = File(outputPath).openWrite();
      await response.stream.pipe(sink);
      await sink.close();
    }
  }

  Future<String?> _findConvertScript() async {
    final searchPaths = [
      if (llamaCppPath != null) '$llamaCppPath/convert_hf_to_gguf.py',
      '${Platform.environment['HOME']}/llama.cpp/convert_hf_to_gguf.py',
      '/usr/local/share/llama.cpp/convert_hf_to_gguf.py',
      '/opt/llama.cpp/convert_hf_to_gguf.py',
    ];

    for (final path in searchPaths) {
      // ignore: avoid_slow_async_io
      if (await File(path).exists()) {
        return path;
      }
    }

    // Try to find via which
    try {
      final result = await Process.run('which', ['convert_hf_to_gguf.py']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (e) {
      // Ignore
    }

    return null;
  }

  Future<String?> _findQuantizeScript() async {
    final searchPaths = [
      if (llamaCppPath != null) '$llamaCppPath/build/bin/llama-quantize',
      if (llamaCppPath != null) '$llamaCppPath/llama-quantize',
      '${Platform.environment['HOME']}/llama.cpp/build/bin/llama-quantize',
      '${Platform.environment['HOME']}/llama.cpp/llama-quantize',
      '/usr/local/bin/llama-quantize',
      '/usr/bin/llama-quantize',
    ];

    for (final path in searchPaths) {
      // ignore: avoid_slow_async_io
      if (await File(path).exists()) {
        return path;
      }
    }

    // Try to find via which
    try {
      final result = await Process.run('which', ['llama-quantize']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (e) {
      // Ignore
    }

    return null;
  }

  /// Get installation instructions for missing dependencies.
  String getInstallInstructions() {
    return '''
=== Model Conversion Requirements ===

1. Python 3.8+ with packages:
   pip install transformers torch safetensors sentencepiece

2. llama.cpp repository:
   git clone https://github.com/ggerganov/llama.cpp
   cd llama.cpp
   make llama-quantize

3. Set llama.cpp path:
   final converter = ModelConverter(
     llamaCppPath: '/path/to/llama.cpp',
   );

=== Alternative: Use Pre-converted GGUF ===

Many models have GGUF versions available:
- Search HuggingFace for "{model-name} GGUF"
- Check unsloth, TheBloke, QuantFactory repos
''';
  }
}
