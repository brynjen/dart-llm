// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Native Assets build hook for llm_llamacpp.
///
/// This hook runs during `flutter pub get` / `flutter build` to:
/// 1. Download prebuilt binaries from GitHub Releases (if available)
/// 2. Fall back to building from source (requires CMake + platform toolchains)
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

/// GitHub repository for downloading prebuilt binaries
const String _githubOwner = 'brynjen';
const String _githubRepo = 'dart-llm';

/// Package version - should match pubspec.yaml
const String _packageVersion = '0.1.0';

/// Asset ID for the llama.cpp library
const String _llamaAssetId = 'package:llm_llamacpp/llama.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    logger.info('Building llm_llamacpp for $targetOS-$targetArch');

    // Determine library name based on OS
    final libraryName = _getLibraryName(targetOS);
    if (libraryName == null) {
      logger.warning('Unsupported OS: $targetOS');
      return;
    }

    // Try to download prebuilt binary first
    final prebuiltPath = await _tryDownloadPrebuilt(
      targetOS,
      targetArch,
      libraryName,
      input,
      logger,
    );

    if (prebuiltPath != null) {
      logger.info('Using prebuilt binary: $prebuiltPath');
      _addCodeAsset(output, prebuiltPath, input);
      return;
    }

    // Fall back to building from source
    logger.info('No prebuilt binary available, building from source...');
    final builtPath = await _buildFromSource(
      targetOS,
      targetArch,
      libraryName,
      input,
      logger,
    );

    if (builtPath != null) {
      logger.info('Built from source: $builtPath');
      _addCodeAsset(output, builtPath, input);
    } else {
      throw Exception(
        'Failed to build llama.cpp for $targetOS-$targetArch. '
        'Please ensure CMake and platform toolchains are installed, '
        'or download prebuilt binaries from GitHub Releases.',
      );
    }
  });
}

String? _getLibraryName(OS os) {
  return switch (os) {
    OS.android => 'libllama.so',
    OS.iOS => 'llama.framework',
    OS.macOS => 'libllama.dylib',
    OS.linux => 'libllama.so',
    OS.windows => 'llama.dll',
    _ => null,
  };
}

/// Returns the architecture string used in GitHub release asset names
String _getArchString(Architecture arch, OS os) {
  if (os == OS.android) {
    return switch (arch) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.arm => 'armeabi-v7a',
      Architecture.x64 => 'x86_64',
      Architecture.ia32 => 'x86',
      _ => arch.toString(),
    };
  }
  return switch (arch) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x64',
    Architecture.arm => 'arm',
    Architecture.ia32 => 'x86',
    _ => arch.toString(),
  };
}

/// Attempts to download prebuilt binary from GitHub Releases
Future<Uri?> _tryDownloadPrebuilt(
  OS targetOS,
  Architecture? targetArch,
  String libraryName,
  BuildInput input,
  Logger logger,
) async {
  if (targetArch == null) {
    logger.warning('Target architecture unknown, cannot download prebuilt');
    return null;
  }

  final archString = _getArchString(targetArch, targetOS);
  final osString = targetOS.toString().toLowerCase();

  // Asset name format: llm_llamacpp-v0.1.0-android-arm64-v8a.zip
  // or for single files: libllama-v0.1.0-linux-x64.so
  final assetName = 'llm_llamacpp-v$_packageVersion-$osString-$archString.zip';
  final downloadUrl = Uri.parse(
    'https://github.com/$_githubOwner/$_githubRepo/releases/download/'
    'v$_packageVersion/$assetName',
  );

  logger.info('Checking for prebuilt at: $downloadUrl');

  try {
    // Create cache directory for downloaded binaries
    final cacheDir = Directory.fromUri(
      input.outputDirectory.resolve('.cache/'),
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final zipFile = File.fromUri(cacheDir.uri.resolve(assetName));
    final extractDir = Directory.fromUri(
      cacheDir.uri.resolve('$osString-$archString/'),
    );

    // Check if already downloaded and extracted
    final libraryFile = File.fromUri(extractDir.uri.resolve(libraryName));
    if (libraryFile.existsSync()) {
      logger.info('Using cached prebuilt binary');
      return libraryFile.uri;
    }

    // Download the asset
    final request = await HttpClient().getUrl(downloadUrl);
    final response = await request.close();

    if (response.statusCode != 200) {
      logger.info(
        'Prebuilt not available (HTTP ${response.statusCode}), will build from source',
      );
      return null;
    }

    logger.info('Downloading prebuilt binary...');
    final bytes = await response.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    await zipFile.writeAsBytes(bytes);

    // Extract the zip
    logger.info('Extracting...');
    if (!extractDir.existsSync()) {
      extractDir.createSync(recursive: true);
    }

    final result = await Process.run('unzip', [
      '-o',
      zipFile.path,
      '-d',
      extractDir.path,
    ]);

    if (result.exitCode != 0) {
      logger.warning('Failed to extract: ${result.stderr}');
      return null;
    }

    if (libraryFile.existsSync()) {
      return libraryFile.uri;
    }

    // Try to find the library in subdirectories
    final found = extractDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(libraryName))
        .firstOrNull;

    return found?.uri;
  } catch (e) {
    logger.info('Failed to download prebuilt: $e');
    return null;
  }
}

/// Builds llama.cpp from source using CMake
Future<Uri?> _buildFromSource(
  OS targetOS,
  Architecture? targetArch,
  String libraryName,
  BuildInput input,
  Logger logger,
) async {
  // Get the package root directory
  final packageRoot = input.packageRoot;
  final llamacppDir = Directory.fromUri(packageRoot.resolve('llamacpp/'));

  if (!llamacppDir.existsSync()) {
    logger.severe(
      'llama.cpp source not found at ${llamacppDir.path}. '
      'Please clone the submodule or download prebuilt binaries.',
    );
    return null;
  }

  final buildDir = Directory.fromUri(
    input.outputDirectory.resolve('build-$targetOS-$targetArch/'),
  );

  if (!buildDir.existsSync()) {
    buildDir.createSync(recursive: true);
  }

  // Configure CMake arguments based on target
  final cmakeArgs = <String>[
    '-S',
    llamacppDir.path,
    '-B',
    buildDir.path,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_EXAMPLES=OFF',
    '-DLLAMA_BUILD_SERVER=OFF',
    '-DLLAMA_BUILD_TOOLS=OFF',
    '-DLLAMA_CURL=OFF',
    '-DBUILD_SHARED_LIBS=ON',
  ];

  // Add platform-specific flags
  if (targetOS == OS.android) {
    final ndkPath =
        Platform.environment['ANDROID_NDK_HOME'] ??
        Platform.environment['ANDROID_NDK'];
    if (ndkPath == null) {
      logger.severe('ANDROID_NDK_HOME not set');
      return null;
    }

    final abi = _getArchString(targetArch!, targetOS);
    cmakeArgs.addAll([
      '-DCMAKE_TOOLCHAIN_FILE=$ndkPath/build/cmake/android.toolchain.cmake',
      '-DANDROID_ABI=$abi',
      '-DANDROID_PLATFORM=android-28',
      '-DGGML_NATIVE=OFF',
      '-DGGML_LLAMAFILE=OFF',
    ]);
  }

  logger.info('Configuring CMake...');
  var result = await Process.run('cmake', cmakeArgs);
  if (result.exitCode != 0) {
    logger.severe('CMake configure failed: ${result.stderr}');
    return null;
  }

  logger.info('Building...');
  result = await Process.run('cmake', [
    '--build',
    buildDir.path,
    '--config',
    'Release',
    '-j${Platform.numberOfProcessors}',
  ]);

  if (result.exitCode != 0) {
    logger.severe('CMake build failed: ${result.stderr}');
    return null;
  }

  // Find the built library
  final possiblePaths = [
    buildDir.uri.resolve('bin/$libraryName'),
    buildDir.uri.resolve('src/$libraryName'),
    buildDir.uri.resolve(libraryName),
  ];

  for (final path in possiblePaths) {
    final file = File.fromUri(path);
    if (file.existsSync()) {
      return file.uri;
    }
  }

  // Search recursively
  final found = buildDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(libraryName))
      .firstOrNull;

  return found?.uri;
}

void _addCodeAsset(
  BuildOutputBuilder output,
  Uri libraryPath,
  BuildInput input,
) {
  output.assets.code.add(
    CodeAsset(
      package: 'llm_llamacpp',
      name: _llamaAssetId,
      linkMode: DynamicLoadingBundled(),
      file: libraryPath,
    ),
  );
}
