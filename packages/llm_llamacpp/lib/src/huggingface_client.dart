import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'model_converter.dart';
import 'model_info.dart';

/// Client for downloading and acquiring models from HuggingFace.
class HuggingFaceClient {
  HuggingFaceClient({http.Client? httpClient, this.llamaCppPath})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Path to llama.cpp repository (for conversion).
  final String? llamaCppPath;

  // ============================================================
  // Model Downloads
  // ============================================================

  /// Download a model from HuggingFace.
  ///
  /// [repoId] - HuggingFace repository ID (e.g., 'Qwen/Qwen2.5-0.5B-Instruct-GGUF').
  /// [filename] - GGUF filename within the repository.
  /// [outputDir] - Directory to save the model.
  /// [revision] - Git revision (branch, tag, or commit). Defaults to 'main'.
  ///
  /// Returns a stream of download progress updates.
  Stream<DownloadProgress> downloadModel(
    String repoId,
    String filename,
    String outputDir, {
    String revision = 'main',
  }) async* {
    final url = 'https://huggingface.co/$repoId/resolve/$revision/$filename';
    final outputPath = '$outputDir/$filename';

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    // Check if file already exists
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final size = await outputFile.length();
      yield DownloadProgress(
        totalBytes: size,
        downloadedBytes: size,
        status: 'Already downloaded',
      );
      return;
    }

    // Start download
    yield DownloadProgress(
      totalBytes: 0,
      downloadedBytes: 0,
      status: 'Starting download...',
    );

    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var downloadedBytes = 0;

    // Create temp file for download
    final tempPath = '$outputPath.download';
    final tempFile = File(tempPath);
    final sink = tempFile.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        yield DownloadProgress(
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          status: 'Downloading...',
        );
      }

      await sink.close();

      // Rename temp file to final name
      await tempFile.rename(outputPath);

      yield DownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        status: 'Complete',
      );
    } catch (e) {
      await sink.close();
      // Clean up temp file on error
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Get download URL for a HuggingFace model.
  String getHuggingFaceUrl(
    String repoId,
    String filename, {
    String revision = 'main',
  }) {
    return 'https://huggingface.co/$repoId/resolve/$revision/$filename';
  }

  /// Parse a HuggingFace model URL.
  ///
  /// Returns (repoId, filename, revision) or null if invalid.
  (String, String, String)? parseHuggingFaceUrl(String url) {
    // https://huggingface.co/{repo_id}/resolve/{revision}/{filename}
    final pattern = RegExp(
      r'https?://huggingface\.co/([^/]+/[^/]+)/resolve/([^/]+)/(.+)',
    );
    final match = pattern.firstMatch(url);
    if (match == null) return null;

    return (match.group(1)!, match.group(3)!, match.group(2)!);
  }

  // ============================================================
  // Model Planning
  // ============================================================

  /// Get the best model option for a HuggingFace repo.
  ///
  /// Returns a recommendation for how to get the model:
  /// - Direct GGUF download (if available)
  /// - Conversion from safetensors (if only safetensors)
  /// - Error (if neither available)
  Future<ModelAcquisitionPlan> planModelAcquisition(
    String repoId, {
    QuantizationType preferredQuantization = QuantizationType.q4_k_m,
  }) async {
    final converter = _createConverter();

    // Check for existing GGUF files
    final ggufFiles = await converter.findGgufFiles(repoId);

    if (ggufFiles.isNotEmpty) {
      // Find best matching quantization
      String? bestMatch;
      for (final file in ggufFiles) {
        final lower = file.toLowerCase();
        if (lower.contains(preferredQuantization.cliName.toLowerCase())) {
          bestMatch = file;
          break;
        }
      }
      bestMatch ??= ggufFiles.first;

      return ModelAcquisitionPlan(
        method: AcquisitionMethod.directDownload,
        repoId: repoId,
        filename: bestMatch,
        availableGgufFiles: ggufFiles,
      );
    }

    // Check for safetensors
    final hasSafetensors = await converter.hasSafetensors(repoId);
    if (hasSafetensors) {
      return ModelAcquisitionPlan(
        method: AcquisitionMethod.convertFromSafetensors,
        repoId: repoId,
        suggestedQuantization: preferredQuantization,
      );
    }

    return ModelAcquisitionPlan(
      method: AcquisitionMethod.notAvailable,
      repoId: repoId,
      error: 'No GGUF or safetensors files found in repository',
    );
  }

  /// Check if a HuggingFace repo has GGUF files available.
  ///
  /// Returns list of GGUF filenames, or empty if only safetensors.
  Future<List<String>> checkForGguf(String repoId) async {
    final converter = _createConverter();
    return converter.findGgufFiles(repoId);
  }

  // ============================================================
  // Simplified Model Acquisition
  // ============================================================

  /// Get a model from HuggingFace - downloads GGUF or converts safetensors.
  ///
  /// This is the simplified API for acquiring models:
  /// - If the repo has GGUF files, downloads the exact quantization match
  /// - If only safetensors, converts to GGUF (requires [quantization])
  ///
  /// The method is **deterministic** - it will only download exact matches
  /// and throws clear errors when there's ambiguity or no match.
  ///
  /// [repoId] - HuggingFace repo (e.g., 'brynjen/memory_core_extraction').
  /// [outputDir] - Directory to save the model (required).
  /// [quantization] - Target quantization. Required if repo only has safetensors.
  ///                  For GGUF repos, defaults to q4_k_m if not specified.
  /// [preferredFile] - Specific GGUF filename to download (bypasses matching).
  /// [revision] - Git revision (default: 'main').
  ///
  /// Returns the path to the downloaded/converted model.
  ///
  /// Throws:
  /// - [ModelNotFoundException] if no matching GGUF file found
  /// - [AmbiguousModelException] if multiple files match
  /// - [ConversionRequiredException] if only safetensors and no quantization specified
  /// - [UnsupportedModelException] if repo has no usable files
  Future<String> getModel(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
  }) async {
    // Use streaming version and collect result
    String? resultPath;

    await for (final status in getModelStream(
      repoId,
      outputDir: outputDir,
      quantization: quantization,
      preferredFile: preferredFile,
      revision: revision,
    )) {
      if (status.isError) {
        throw Exception(status.error ?? 'Model acquisition failed');
      }
      if (status.isComplete) {
        resultPath = status.modelPath;
      }
    }

    if (resultPath == null) {
      throw Exception('Model acquisition completed but no path returned');
    }

    return resultPath;
  }

  /// Stream version of [getModel] with progress updates.
  ///
  /// Use this for UI progress feedback or long-running downloads.
  Stream<ModelAcquisitionStatus> getModelStream(
    String repoId, {
    required String outputDir,
    QuantizationType? quantization,
    String? preferredFile,
    String revision = 'main',
  }) async* {
    // Default to q4_k_m for GGUF matching if not specified
    final targetQuant = quantization ?? QuantizationType.q4_k_m;

    yield ModelAcquisitionStatus(
      stage: ModelAcquisitionStage.checking,
      message: 'Checking repository files...',
    );

    // List files in the repository
    final converter = _createConverter();
    List<HfModelFile> files;
    try {
      files = await converter.listRepoFiles(repoId, revision: revision);
    } catch (e) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.failed,
        message: 'Failed to list repository files',
        error: e.toString(),
      );
      return;
    }

    final ggufFiles = files
        .where((f) => f.filename.toLowerCase().endsWith('.gguf'))
        .toList();
    final hasSafetensors = files.any(
      (f) => f.filename.endsWith('.safetensors'),
    );

    // CASE 1: Specific file requested
    if (preferredFile != null) {
      final match = ggufFiles
          .where((f) => f.filename == preferredFile)
          .toList();
      if (match.isEmpty) {
        throw ModelNotFoundException(
          repoId: repoId,
          message: "File '$preferredFile' not found in repository",
          availableFiles: ggufFiles.map((f) => f.filename).toList(),
        );
      }

      yield* _downloadGgufFile(
        repoId: repoId,
        filename: preferredFile,
        outputDir: outputDir,
        revision: revision,
      );
      return;
    }

    // CASE 2: Repository has GGUF files
    if (ggufFiles.isNotEmpty) {
      // Find exact quantization match
      final quantPattern = RegExp(targetQuant.cliName, caseSensitive: false);
      final matches = ggufFiles
          .where((f) => quantPattern.hasMatch(f.filename))
          .toList();

      if (matches.isEmpty) {
        throw ModelNotFoundException(
          repoId: repoId,
          message: 'No ${targetQuant.displayName} GGUF found',
          availableFiles: ggufFiles
              .map((f) => '${f.filename} (${_formatSize(f.size)})')
              .toList(),
        );
      }

      if (matches.length > 1) {
        throw AmbiguousModelException(
          repoId: repoId,
          message: 'Multiple ${targetQuant.displayName} files found',
          matchingFiles: matches.map((f) => f.filename).toList(),
        );
      }

      // Single exact match - download it
      yield* _downloadGgufFile(
        repoId: repoId,
        filename: matches.first.filename,
        outputDir: outputDir,
        revision: revision,
        fileSize: matches.first.size,
      );
      return;
    }

    // CASE 3: Only safetensors - conversion required
    if (hasSafetensors) {
      // Quantization must be explicitly specified for conversion
      if (quantization == null) {
        throw ConversionRequiredException(
          repoId: repoId,
          message: 'Quantization required for safetensors conversion',
        );
      }

      yield* _convertFromSafetensors(
        repoId: repoId,
        outputDir: outputDir,
        quantization: quantization,
        revision: revision,
      );
      return;
    }

    // CASE 4: No usable files
    throw UnsupportedModelException(
      repoId: repoId,
      message: 'Repository has no GGUF or safetensors files',
    );
  }

  /// Download a specific GGUF file from HuggingFace.
  Stream<ModelAcquisitionStatus> _downloadGgufFile({
    required String repoId,
    required String filename,
    required String outputDir,
    required String revision,
    int? fileSize,
  }) async* {
    final outputPath = '$outputDir/$filename';

    // Check if already exists
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final existingSize = await outputFile.length();
      if (fileSize == null || existingSize == fileSize) {
        yield ModelAcquisitionStatus(
          stage: ModelAcquisitionStage.complete,
          message: 'Model already downloaded',
          modelPath: outputPath,
        );
        return;
      }
    }

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    yield ModelAcquisitionStatus(
      stage: ModelAcquisitionStage.downloading,
      message: 'Downloading $filename...',
      progress: 0.0,
    );

    // Download the file
    await for (final progress in downloadModel(
      repoId,
      filename,
      outputDir,
      revision: revision,
    )) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.downloading,
        message: progress.status ?? 'Downloading...',
        progress: progress.progress,
      );

      if (progress.isComplete) {
        yield ModelAcquisitionStatus(
          stage: ModelAcquisitionStage.complete,
          message: 'Download complete',
          modelPath: outputPath,
        );
      }
    }
  }

  /// Convert safetensors to GGUF with specified quantization.
  Stream<ModelAcquisitionStatus> _convertFromSafetensors({
    required String repoId,
    required String outputDir,
    required QuantizationType quantization,
    required String revision,
  }) async* {
    // Generate output filename
    final repoName = repoId.split('/').last.toLowerCase();
    final outputFilename = '$repoName-${quantization.cliName}.gguf';
    final outputPath = '$outputDir/$outputFilename';

    // Check if already exists
    if (await File(outputPath).exists()) {
      yield ModelAcquisitionStatus(
        stage: ModelAcquisitionStage.complete,
        message: 'Converted model already exists',
        modelPath: outputPath,
      );
      return;
    }

    // Create output directory
    await Directory(outputDir).create(recursive: true);

    // Run conversion
    final converter = _createConverter();
    await for (final progress in converter.convertFromHuggingFace(
      repoId: repoId,
      outputPath: outputPath,
      quantization: quantization,
    )) {
      final stage = switch (progress.stage) {
        ConversionStage.checking => ModelAcquisitionStage.checking,
        ConversionStage.downloading => ModelAcquisitionStage.downloading,
        ConversionStage.converting => ModelAcquisitionStage.converting,
        ConversionStage.quantizing => ModelAcquisitionStage.quantizing,
        ConversionStage.cleanup => ModelAcquisitionStage.converting,
        ConversionStage.complete => ModelAcquisitionStage.complete,
        ConversionStage.failed => ModelAcquisitionStage.failed,
      };

      yield ModelAcquisitionStatus(
        stage: stage,
        message: progress.message,
        progress: progress.progress,
        modelPath: progress.isComplete ? outputPath : null,
        error: progress.error,
      );
    }
  }

  ModelConverter _createConverter() {
    return ModelConverter(llamaCppPath: llamaCppPath, httpClient: _httpClient);
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  /// Close the HTTP client.
  void close() {
    _httpClient.close();
  }
}
