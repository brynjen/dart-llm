// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Native Assets build hook for llm_llamacpp.
///
/// This hook runs during `flutter pub get` / `flutter build` to:
/// 1. Download prebuilt binaries from GitHub Releases (if available)
/// 2. Fall back to building from source (requires CMake + platform toolchains)
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// GitHub repository for downloading prebuilt binaries.
const String _githubOwner = 'brynjen';
const String _githubRepo = 'dart-llm';

/// Fallback native artifact version, used only if `pubspec.yaml` cannot be
/// read or parsed. The real value comes from [_readNativeBinaryVersion].
const String _fallbackNativeBinaryVersion = '0.3.1';

/// The GitHub release that carries this package's prebuilt native bundles.
///
/// Read straight from `version:` in the package's own `pubspec.yaml`, so it can
/// never drift from the published package version. The hook requests
/// `.../releases/download/<version>/llm_llamacpp-v<version>-abi<fp>-...zip`,
/// so a release tagged `<version>` — no `v` prefix — must carry assets built
/// from these bindings. `.github/workflows/build-release.yaml` reads the same field, which
/// is what keeps the two ends in agreement: bumping the package version is all
/// it takes to get a matching release built and to point this hook at it.
///
/// A published package does not carry the `llamacpp/` submodule, so for pub.dev
/// consumers the prebuilt is the only path — a missing release means a hard
/// build failure, not a slow from-source fallback.
///
/// Note: prebuilt asset filenames also include an ABI fingerprint (see
/// [_computeAbiFingerprint]) so that updates to the FFI binding surface
/// automatically invalidate incompatible prebuilt bundles even without a
/// version bump.
String _readNativeBinaryVersion(Uri packageRoot, Logger? logger) {
  final pubspec = File.fromUri(packageRoot.resolve(_pubspecPath));
  if (!pubspec.existsSync()) {
    logger?.warning(
      'Could not read ${pubspec.path}; falling back to native artifact '
      'version $_fallbackNativeBinaryVersion.',
    );
    return _fallbackNativeBinaryVersion;
  }
  // Top-level `version:` only — a nested or commented occurrence must not win.
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  logger?.warning(
    'No top-level `version:` in ${pubspec.path}; falling back to native '
    'artifact version $_fallbackNativeBinaryVersion.',
  );
  return _fallbackNativeBinaryVersion;
}

/// Path to the package's pubspec, relative to the package root.
const String _pubspecPath = 'pubspec.yaml';

/// Test-only entry point for [_readNativeBinaryVersion].
///
/// `test/unit/native_binary_version_test.dart` uses this to assert that the
/// version the hook requests prebuilts for is exactly the package version, and
/// that `.github/workflows/build-release.yaml` would resolve the same string.
String readNativeBinaryVersionForTesting(Uri packageRoot) =>
    _readNativeBinaryVersion(packageRoot, null);

/// Files whose hash defines the FFI ABI contract we expect from the loaded
/// native library at runtime. If any of these change (e.g. because the
/// `llamacpp/` submodule was updated and bindings were regenerated), the
/// fingerprint changes, which:
///
///   * appends a new path segment to the local prebuilt cache so a stale
///     extract from a previous fingerprint can never be reused, and
///   * changes the GitHub Releases asset filename so that we either fetch a
///     prebuilt that was built against the same ABI or fall through to a
///     from-source build.
///
/// Paths are relative to the package root.
const List<String> _abiFingerprintInputs = [
  'lib/src/bindings/llama_bindings.dart',
];

const String _preferredAndroidNdkVersion = '26.3.11579264';

const List<String> _androidCoreLibraries = [
  'libllama.so',
  'libggml.so',
  'libggml-base.so',
];

/// Optional Android backend libraries that may be present in the bundle.
///
/// These are GPU/accelerator backends. They are bundled when available, but
/// their absence is not fatal — runtime will simply fall back to CPU.
const List<String> _androidOptionalBackendLibraries = ['libggml-vulkan.so'];

/// ggml libraries that every non-Android shared-library build must produce.
///
/// The CMake configuration below passes `-DBUILD_SHARED_LIBS=ON`, so llama.cpp
/// links against separate `ggml` shared libraries instead of absorbing them.
/// Bundling only the primary library therefore ships an app that cannot
/// resolve its own dependencies at load time.
///
/// Named by *stem* (no `lib` prefix, no extension) because Windows drops the
/// prefix: `ggml` is `libggml.dylib`, `libggml.so`, or `ggml.dll`.
const List<String> _desktopCoreLibraryStems = ['ggml', 'ggml-base'];

/// Matches the macOS versioned aliases CMake emits next to the plain name,
/// e.g. `libggml.0.dylib` and `libggml.0.20.1.dylib` beside `libggml.dylib`.
///
/// Only the unversioned name is collected: it is a symlink onto the very same
/// binary, and it is the name the runtime loaders ask for. Flutter rewrites the
/// Mach-O install names of everything it bundles (it reads the current install
/// name with `otool -D`), so emitting the unversioned alias still fixes up
/// dependents that reference the versioned `@rpath/libggml.0.dylib`.
///
/// Linux needs no equivalent: its versioned aliases are `libggml.so.0` and
/// `libggml.so.0.20.1`, which already fail the `.so` extension test.
final RegExp _versionedLibraryStemSuffix = RegExp(r'\.\d+(?:\.\d+)*$');

void main(List<String> args) async {
  await build(args, (input, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      // ignore: avoid_print
      ..onRecord.listen((record) => print(record.message));

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    logger.info('Building llm_llamacpp for $targetOS-$targetArch');

    // Determine library name based on OS.
    final libraryName = _getPrimaryLibraryName(targetOS);
    if (libraryName == null) {
      logger.warning('Unsupported OS: $targetOS');
      return;
    }

    final abiFingerprint = _computeAbiFingerprint(input.packageRoot);
    final nativeBinaryVersion = _readNativeBinaryVersion(
      input.packageRoot,
      logger,
    );
    logger.info(
      'ABI fingerprint: $abiFingerprint '
      '(derived from ${_abiFingerprintInputs.join(', ')}); '
      'native artifact version: $nativeBinaryVersion',
    );

    // Declare the fingerprint inputs as hook dependencies. Without this the
    // hooks runner reuses the cached output whenever nothing else changed, so
    // regenerating the bindings would *not* re-run this hook and the ABI
    // fingerprint would never be recomputed -- silently defeating the whole
    // invalidation scheme above. `pubspec.yaml` is declared for the same
    // reason: it now supplies the release version the prebuilt is fetched from.
    for (final relative in [..._abiFingerprintInputs, _pubspecPath]) {
      output.dependencies.add(input.packageRoot.resolve(relative));
    }

    final prebuiltLibraries = await _tryDownloadPrebuilt(
      targetOS,
      targetArch,
      libraryName,
      input,
      logger,
      abiFingerprint,
      nativeBinaryVersion,
    );

    if (prebuiltLibraries != null) {
      logger.info('Using ${prebuiltLibraries.length} prebuilt native asset(s)');
      _addCodeAssets(output, prebuiltLibraries, input);
      return;
    }

    // Fall back to building from source.
    logger.info('No prebuilt binary available, building from source...');
    final builtLibraries = await _buildFromSource(
      targetOS,
      targetArch,
      libraryName,
      input,
      logger,
    );

    if (builtLibraries != null && builtLibraries.isNotEmpty) {
      logger.info('Built ${builtLibraries.length} native asset(s) from source');
      _addCodeAssets(output, builtLibraries, input);
    } else {
      throw Exception(
        'Failed to build llama.cpp for $targetOS-$targetArch. '
        'Please ensure CMake and platform toolchains are installed, '
        'or download prebuilt binaries from GitHub Releases.',
      );
    }
  });
}

/// Computes a short, stable fingerprint of the FFI bindings surface.
///
/// The hash is normalized for line endings so the value is identical when
/// computed in the Dart hook (Windows/macOS/Linux developer machines) and in
/// the GitHub Actions release workflow (Linux). The first 12 hex chars of
/// SHA-256 give us ~48 bits of collision resistance, which is plenty for cache
/// keying across a handful of public releases.
String _computeAbiFingerprint(Uri packageRoot) =>
    computeAbiFingerprintForTesting(
      packageRoot: packageRoot,
      relativeInputs: _abiFingerprintInputs,
    );

/// Test-only entry point. Mirrors the production fingerprint computation so
/// `test/unit/abi_fingerprint_test.dart` can exercise it against a controlled
/// directory. MUST stay byte-identical to what the GitHub Actions workflow
/// computes (see `.github/workflows/build-release.yaml#abi-fingerprint`).
String computeAbiFingerprintForTesting({
  required Uri packageRoot,
  required List<String> relativeInputs,
}) {
  final buffer = <int>[];
  for (final relative in relativeInputs) {
    final file = File.fromUri(packageRoot.resolve(relative));
    if (!file.existsSync()) {
      throw Exception(
        'ABI fingerprint input not found: ${file.path}. '
        'Cannot safely choose between prebuilt and source build.',
      );
    }
    final raw = file.readAsBytesSync();
    // Include the path (with delimiters) so file ordering matters and
    // adding/removing files would change the hash.
    buffer.addAll(utf8.encode(relative));
    buffer.add(0);
    buffer.addAll(_normalizeLineEndings(raw));
    buffer.add(0);
  }
  // 12 hex chars (= 6 bytes) gives ~48 bits of collision resistance, which is
  // plenty for keying a handful of public releases and developer caches.
  return sha256.convert(buffer).toString().substring(0, 12);
}

/// Strips `\r` bytes so the hash is invariant to git's autocrlf mangling on
/// Windows checkouts.
List<int> _normalizeLineEndings(List<int> bytes) {
  final out = <int>[];
  for (final b in bytes) {
    if (b == 0x0D) continue;
    out.add(b);
  }
  return out;
}

String? _getPrimaryLibraryName(OS os) {
  return switch (os) {
    OS.android => 'libllama.so',
    OS.iOS => 'llama.framework',
    OS.macOS => 'libllama.dylib',
    OS.linux => 'libllama.so',
    OS.windows => 'llama.dll',
    _ => null,
  };
}

/// Returns the architecture string used in GitHub release asset names.
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

/// Attempts to download prebuilt binaries from GitHub Releases.
Future<List<Uri>?> _tryDownloadPrebuilt(
  OS targetOS,
  Architecture? targetArch,
  String libraryName,
  BuildInput input,
  Logger logger,
  String abiFingerprint,
  String nativeBinaryVersion,
) async {
  if (targetArch == null) {
    logger.warning('Target architecture unknown, cannot download prebuilt');
    return null;
  }

  final archString = _getArchString(targetArch, targetOS);
  final osString = targetOS.toString().toLowerCase();

  // The ABI fingerprint participates in the asset filename, so the URL itself
  // is invalidated the moment the FFI bindings change. A 404 cleanly falls
  // through to the from-source build path below.
  final assetName =
      'llm_llamacpp-v$nativeBinaryVersion-abi$abiFingerprint'
      '-$osString-$archString.zip';
  final downloadUrl = Uri.parse(
    // The release tag is the bare version, with no `v` prefix.
    'https://github.com/$_githubOwner/$_githubRepo/releases/download/'
    '$nativeBinaryVersion/$assetName',
  );

  logger.info('Checking for prebuilt at: $downloadUrl');

  // The download cache lives in `outputDirectoryShared`, not `outputDirectory`:
  // the latter is per-config (nested inside the shared directory under a
  // config-derived checksum), so caching there would re-download the bundle for
  // every target OS/architecture. The cache key below already carries the
  // os/arch discriminators needed to share one directory safely.
  final cacheDir = Directory.fromUri(
    input.outputDirectoryShared.resolve('.cache/'),
  );
  if (!cacheDir.existsSync()) {
    cacheDir.createSync(recursive: true);
  }

  final zipFile = File.fromUri(cacheDir.uri.resolve(assetName));
  // The local cache key mirrors the asset name: bumping the version OR
  // regenerating the bindings (changing the ABI fingerprint) yields a fresh
  // path so a stale extract from a previous fingerprint can never be reused.
  // Without this, an old extract on disk is silently treated as compatible —
  // the exact failure mode that produces near-uniform-logit "multilingual
  // gibberish" output instead of a hard crash.
  final extractDir = Directory.fromUri(
    cacheDir.uri.resolve(
      'v$nativeBinaryVersion-abi$abiFingerprint-$osString-$archString/',
    ),
  );

  if (_findEntityNamed(extractDir, libraryName) != null) {
    logger.info('Using cached prebuilt binary bundle');
    return _collectPrebuiltNativeLibraries(
      targetOS: targetOS,
      targetArch: targetArch,
      libraryName: libraryName,
      bundleDirectory: extractDir,
      logger: logger,
    );
  }

  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(downloadUrl);
    final response = await request.close();

    if (response.statusCode != 200) {
      await response.drain<void>();
      logger.info(
        'Prebuilt not available (HTTP ${response.statusCode}), will build from source',
      );
      return null;
    }

    logger.info('Downloading prebuilt binary bundle...');
    final bytes = await response.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    await zipFile.writeAsBytes(bytes);

    logger.info('Extracting...');
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    extractDir.createSync(recursive: true);

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
  } catch (e) {
    logger.info('Failed to download prebuilt: $e');
    return null;
  } finally {
    httpClient.close(force: true);
  }

  return _collectPrebuiltNativeLibraries(
    targetOS: targetOS,
    targetArch: targetArch,
    libraryName: libraryName,
    bundleDirectory: extractDir,
    logger: logger,
  );
}

/// Collects a downloaded bundle, degrading to a source build when it is
/// incomplete.
///
/// A published bundle can predate a change to what we require (the desktop
/// bundles released before the ggml libraries were collected are exactly that
/// case). Treating an incomplete bundle as "no prebuilt available" keeps such a
/// release from bricking the build: the caller just compiles from source.
Future<List<Uri>?> _collectPrebuiltNativeLibraries({
  required OS targetOS,
  required Architecture targetArch,
  required String libraryName,
  required Directory bundleDirectory,
  required Logger logger,
}) async {
  try {
    return await _collectNativeLibraries(
      targetOS: targetOS,
      targetArch: targetArch,
      libraryName: libraryName,
      bundleDirectory: bundleDirectory,
      outputDirectory: bundleDirectory,
      logger: logger,
    );
  } on Exception catch (error) {
    logger.warning(
      'Prebuilt bundle in ${bundleDirectory.path} is unusable ($error). '
      'Falling back to a source build.',
    );
    return null;
  }
}

Future<List<Uri>> _collectNativeLibraries({
  required OS targetOS,
  required Architecture targetArch,
  required String libraryName,
  required Directory bundleDirectory,
  required Directory outputDirectory,
  required Logger logger,
}) async {
  if (targetOS == OS.android) {
    final abi = _getArchString(targetArch, targetOS);
    return _collectAndroidNativeLibraries(
      bundleDirectory: bundleDirectory,
      outputDirectory: outputDirectory,
      abi: abi,
      openMpRequired: _androidOpenMpRequired(abi),
      logger: logger,
    );
  }

  final library = _findEntityNamed(bundleDirectory, libraryName);
  if (library == null) {
    throw Exception(
      'Missing native library $libraryName in ${bundleDirectory.path}',
    );
  }

  if (targetOS == OS.iOS) {
    // iOS ships a single `llama.framework` rather than loose shared libraries,
    // so there are no sibling ggml libraries to collect.
    return <Uri>[library.uri];
  }

  return _collectDesktopNativeLibraries(
    targetOS: targetOS,
    primaryLibrary: library,
    logger: logger,
  );
}

/// Test helper for macOS/Linux/Windows bundle collection.
///
/// Non-private for the same reason as
/// [collectAndroidNativeLibrariesForTesting]: it lets tests exercise the
/// selection and ordering rules without a network download or a native build.
Future<List<Uri>> collectDesktopNativeLibrariesForTesting({
  required OS targetOS,
  required Uri bundleDirectory,
  required String libraryName,
}) async {
  final library = _findEntityNamed(
    Directory.fromUri(bundleDirectory),
    libraryName,
  );
  if (library == null) {
    throw Exception(
      'Missing native library $libraryName in ${bundleDirectory.toFilePath()}',
    );
  }
  return _collectDesktopNativeLibraries(
    targetOS: targetOS,
    primaryLibrary: library,
    logger: Logger.detached('llm_llamacpp_test'),
  );
}

/// Collects the primary library plus the ggml libraries built alongside it.
///
/// `-DBUILD_SHARED_LIBS=ON` splits llama.cpp across `libllama` and a family of
/// `ggml` libraries, and the primary library carries load commands for each of
/// them. Emitting only the primary one produces an app bundle that fails to
/// resolve its dependencies the moment it is run anywhere other than the
/// machine that built it (the build tree's absolute `LC_RPATH` is the only
/// reason it appears to work locally).
///
/// The returned order mirrors [_collectAndroidNativeLibraries]: primary,
/// core ggml libraries, CPU backends, then remaining backends. It is fully
/// deterministic so the emitted asset list does not churn between builds.
Future<List<Uri>> _collectDesktopNativeLibraries({
  required OS targetOS,
  required FileSystemEntity primaryLibrary,
  required Logger logger,
}) async {
  // Search only the directory that produced the primary library. A CMake tree
  // can hold several copies of the same file name (a host-tools sub-build, for
  // instance), and the siblings of libllama are the ones it is linked against.
  final searchDirectory = Directory(p.dirname(primaryLibrary.path));

  final librariesByStem = <String, File>{};
  final entries = searchDirectory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in entries) {
    final stem = _sharedLibraryStem(p.basename(file.path), targetOS);
    if (stem == null) continue;
    if (_versionedLibraryStemSuffix.hasMatch(stem)) continue;
    if (stem != 'ggml' && !stem.startsWith('ggml-')) continue;
    librariesByStem.putIfAbsent(stem, () => file);
  }

  final missingCoreLibraries = [
    for (final stem in _desktopCoreLibraryStems)
      if (!librariesByStem.containsKey(stem))
        _sharedLibraryFileName(stem, targetOS),
  ];
  if (missingCoreLibraries.isNotEmpty) {
    throw Exception(
      'Missing required native libraries next to '
      '${p.basename(primaryLibrary.path)} in ${searchDirectory.path}: '
      '${missingCoreLibraries.join(', ')}. llama.cpp is configured with '
      '-DBUILD_SHARED_LIBS=ON, so these are separate files that must be '
      'bundled with the primary library.',
    );
  }

  final cpuBackendStems =
      librariesByStem.keys
          .where((stem) => stem == 'ggml-cpu' || stem.startsWith('ggml-cpu-'))
          .toList()
        ..sort();
  if (cpuBackendStems.isEmpty) {
    throw Exception(
      'Missing CPU backend library in ${searchDirectory.path}: '
      'expected at least one ${_sharedLibraryFileName('ggml-cpu*', targetOS)}',
    );
  }

  final optionalBackendStems =
      librariesByStem.keys
          .where(
            (stem) =>
                !_desktopCoreLibraryStems.contains(stem) &&
                !cpuBackendStems.contains(stem),
          )
          .toList()
        ..sort();
  for (final stem in optionalBackendStems) {
    logger.info(
      'Including optional backend library: '
      '${_sharedLibraryFileName(stem, targetOS)}',
    );
  }

  Uri dependency(String stem) =>
      _linkerVisibleLibrary(librariesByStem[stem]!, stem, targetOS).uri;

  return <Uri>[
    // The primary library keeps its plain name: it is the one the runtime
    // loaders pass to `DynamicLibrary.open`, not one the linker resolves.
    primaryLibrary.uri,
    for (final stem in _desktopCoreLibraryStems) dependency(stem),
    for (final stem in cpuBackendStems) dependency(stem),
    for (final stem in optionalBackendStems) dependency(stem),
  ];
}

/// Returns the alias of [library] that the dynamic linker will actually ask
/// for when it resolves a dependency on it.
///
/// On ELF platforms the dependent records the *soname* (`libggml.so.0`), not
/// the development name (`libggml.so`), and nothing rewrites it on the way into
/// the app bundle — so the soname alias is the file that has to be shipped.
///
/// Mach-O needs no equivalent: Flutter reads each bundled dylib's current
/// install name with `otool -D` and rewrites both it and every reference to it,
/// so the plain name is bundled and dependents are repointed at it. Windows
/// DLLs are not versioned at all.
File _linkerVisibleLibrary(File library, String stem, OS os) {
  if (os != OS.linux) return library;

  final directory = Directory(p.dirname(library.path));
  final soname = RegExp(
    '^${RegExp.escape('lib$stem.so')}\\.\\d+(?:\\.\\d+)*\$',
  );
  final aliases =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => soname.hasMatch(p.basename(file.path)))
          .toList()
        // Shortest name first: `libggml.so.0` (the soname) sorts ahead of
        // `libggml.so.0.20.1` (the fully versioned real file).
        ..sort((a, b) {
          final byLength = p
              .basename(a.path)
              .length
              .compareTo(p.basename(b.path).length);
          return byLength != 0 ? byLength : a.path.compareTo(b.path);
        });

  return aliases.isEmpty ? library : aliases.first;
}

/// Shared-library file extension for [os], or `null` if [os] does not use
/// loose shared libraries.
String? _sharedLibraryExtension(OS os) => switch (os) {
  OS.android || OS.linux => '.so',
  OS.macOS => '.dylib',
  OS.windows => '.dll',
  _ => null,
};

/// Shared libraries carry a `lib` prefix everywhere except Windows.
String _sharedLibraryPrefix(OS os) => os == OS.windows ? '' : 'lib';

String _sharedLibraryFileName(String stem, OS os) =>
    '${_sharedLibraryPrefix(os)}$stem${_sharedLibraryExtension(os) ?? ''}';

/// Inverse of [_sharedLibraryFileName]: `libggml-cpu.dylib` -> `ggml-cpu`.
///
/// Returns `null` when [basename] is not a shared library for [os], which also
/// filters out the Linux versioned aliases (`libggml.so.0`).
String? _sharedLibraryStem(String basename, OS os) {
  final extension = _sharedLibraryExtension(os);
  if (extension == null || !basename.endsWith(extension)) return null;
  final prefix = _sharedLibraryPrefix(os);
  if (!basename.startsWith(prefix)) return null;
  return basename.substring(prefix.length, basename.length - extension.length);
}

/// Test helper for Android bundle collection.
///
/// This is intentionally non-private so tests can exercise the hosted-package
/// bundle logic without invoking network downloads or native builds.
Future<List<Uri>> collectAndroidNativeLibrariesForTesting({
  required Uri bundleDirectory,
  required Uri outputDirectory,
  required String abi,
  required bool openMpRequired,
  String? androidNdkPath,
}) {
  return _collectAndroidNativeLibraries(
    bundleDirectory: Directory.fromUri(bundleDirectory),
    outputDirectory: Directory.fromUri(outputDirectory),
    abi: abi,
    openMpRequired: openMpRequired,
    androidNdkPath: androidNdkPath,
    logger: Logger.detached('llm_llamacpp_test'),
  );
}

Future<List<Uri>> _collectAndroidNativeLibraries({
  required Directory bundleDirectory,
  required Directory outputDirectory,
  required String abi,
  required bool openMpRequired,
  required Logger logger,
  String? androidNdkPath,
}) async {
  if (!bundleDirectory.existsSync()) {
    throw Exception('Android native bundle not found: ${bundleDirectory.path}');
  }

  final filesByName = <String, File>{};
  final files =
      bundleDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.so')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    filesByName.putIfAbsent(p.basename(file.path), () => file);
  }

  final missingCoreLibraries = [
    for (final library in _androidCoreLibraries)
      if (!filesByName.containsKey(library)) library,
  ];
  if (missingCoreLibraries.isNotEmpty) {
    throw Exception(
      'Missing required Android native libraries in ${bundleDirectory.path}: '
      '${missingCoreLibraries.join(', ')}',
    );
  }

  final cpuBackendLibraries =
      filesByName.keys
          .where(
            (name) => name.startsWith('libggml-cpu') && name.endsWith('.so'),
          )
          .toList()
        ..sort();
  if (cpuBackendLibraries.isEmpty) {
    throw Exception(
      'Missing Android CPU backend libraries in ${bundleDirectory.path}: '
      'expected at least one libggml-cpu*.so',
    );
  }

  final optionalBackendLibraries = [
    for (final library in _androidOptionalBackendLibraries)
      if (filesByName.containsKey(library)) library,
  ];
  for (final library in optionalBackendLibraries) {
    logger.info('Including optional Android backend library: $library');
  }

  final nativeLibraries = <File>[
    for (final library in _androidCoreLibraries) filesByName[library]!,
    for (final library in cpuBackendLibraries) filesByName[library]!,
    for (final library in optionalBackendLibraries) filesByName[library]!,
  ];

  final bundledOpenMp = filesByName['libomp.so'];
  if (bundledOpenMp != null) {
    nativeLibraries.add(bundledOpenMp);
  } else if (openMpRequired) {
    final copiedOpenMp = await _copyAndroidOpenMpRuntime(
      abi: abi,
      outputDirectory: outputDirectory,
      androidNdkPath: androidNdkPath,
      logger: logger,
    );
    nativeLibraries.add(copiedOpenMp);
  }

  return nativeLibraries.map((file) => file.uri).toList();
}

bool _androidOpenMpRequired(String abi) {
  // The 0.2.0 release enables GGML_OPENMP for arm64-v8a only.
  return abi == 'arm64-v8a';
}

bool _androidCpuAllVariantsEnabled(String abi) {
  // llama.cpp Android CPU variants target modern 64-bit ARM feature sets. They
  // are useful on real edge devices, but invalid for 32-bit ARM fallback builds.
  return abi == 'arm64-v8a';
}

/// Determines whether the Vulkan GPU backend should be built for Android.
///
/// Vulkan is only meaningful on 64-bit ARM (real Android devices). It also
/// requires a host SPIR-V compiler (`glslc`) on PATH so that the
/// `vulkan-shaders-gen` step can produce the embedded shader blobs.
///
/// Default policy:
///   * On Android arm64-v8a we *attempt* Vulkan whenever `glslc` is detected.
///     If the toolchain is missing we skip Vulkan with a friendly hint
///     instead of failing the build.
///   * Set `LLM_LLAMACPP_ANDROID_VULKAN=0` (or `false`) to force-disable.
///   * Set `LLM_LLAMACPP_ANDROID_VULKAN=1` (or `true`) to force-enable, in
///     which case a missing `glslc` becomes a hard build error rather than a
///     silent fallback (useful in CI).
bool _androidVulkanEnabled(String abi, Logger logger) {
  if (abi != 'arm64-v8a') {
    return false;
  }
  final raw = Platform.environment['LLM_LLAMACPP_ANDROID_VULKAN'];
  final override = _parseTriStateFlag(raw);
  if (override == false) {
    logger.info('Vulkan backend disabled by LLM_LLAMACPP_ANDROID_VULKAN=$raw');
    return false;
  }

  final hasGlslc = _hasExecutableOnPath('glslc');
  if (!hasGlslc) {
    if (override == true) {
      throw Exception(
        'LLM_LLAMACPP_ANDROID_VULKAN=$raw was set but `glslc` is not on PATH. '
        'Install the Vulkan SDK / shaderc tools (e.g. `brew install shaderc`, '
        '`apt install glslc`) or unset the variable to allow CPU-only builds.',
      );
    }
    logger.info(
      'Vulkan backend not enabled: `glslc` (SPIR-V shader compiler) was not '
      'found on PATH. Building CPU-only. Install shaderc/glslc and rebuild '
      'to enable GPU offload, or set LLM_LLAMACPP_ANDROID_VULKAN=0 to '
      'silence this hint.',
    );
    return false;
  }

  logger.info(
    'Vulkan backend enabled (glslc detected on PATH). '
    'Set LLM_LLAMACPP_ANDROID_VULKAN=0 to opt out.',
  );
  return true;
}

/// Parses `LLM_LLAMACPP_ANDROID_VULKAN`-style flags. Returns:
///   * `true`  if the user explicitly opted in,
///   * `false` if the user explicitly opted out,
///   * `null`  if the variable is unset / empty (use the default policy).
bool? _parseTriStateFlag(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v == '0' || v == 'false' || v == 'no' || v == 'off') return false;
  if (v == '1' || v == 'true' || v == 'yes' || v == 'on') return true;
  return null;
}

bool _hasExecutableOnPath(String name) {
  final pathEnv = Platform.environment['PATH'];
  if (pathEnv == null || pathEnv.isEmpty) {
    return false;
  }
  final separator = Platform.isWindows ? ';' : ':';
  final exeSuffixes = Platform.isWindows
      ? const ['', '.exe', '.bat']
      : const [''];
  for (final dir in pathEnv.split(separator)) {
    if (dir.isEmpty) continue;
    for (final suffix in exeSuffixes) {
      final candidate = File(p.join(dir, '$name$suffix'));
      if (candidate.existsSync()) {
        return true;
      }
    }
  }
  return false;
}

Future<File> _copyAndroidOpenMpRuntime({
  required String abi,
  required Directory outputDirectory,
  required String? androidNdkPath,
  required Logger logger,
}) async {
  final ompArch = _androidOpenMpArch(abi);
  if (ompArch == null) {
    throw Exception('No OpenMP runtime ABI mapping for Android ABI $abi');
  }

  final ndkDirectory = _findAndroidNdk(androidNdkPath: androidNdkPath);
  if (ndkDirectory == null) {
    throw Exception(
      'libomp.so is required for Android ABI $abi, but no Android NDK was '
      'found. Set ANDROID_NDK_HOME or ANDROID_NDK.',
    );
  }

  final source = _findLibompInNdk(ndkDirectory, ompArch);
  if (source == null) {
    throw Exception(
      'libomp.so is required for Android ABI $abi, but it was not found in '
      '${ndkDirectory.path} for NDK architecture $ompArch.',
    );
  }

  if (!outputDirectory.existsSync()) {
    outputDirectory.createSync(recursive: true);
  }

  final target = File(p.join(outputDirectory.path, 'libomp.so'));
  logger.info('Copying Android OpenMP runtime from ${source.path}');
  await source.copy(target.path);
  return target;
}

String? _androidOpenMpArch(String abi) {
  return switch (abi) {
    'arm64-v8a' => 'aarch64',
    'armeabi-v7a' => 'arm',
    'x86_64' => 'x86_64',
    'x86' => 'i386',
    _ => null,
  };
}

Directory? _findAndroidNdk({String? androidNdkPath}) {
  final candidates = <Directory>[];

  void addDirectory(String? path) {
    if (path != null && path.isNotEmpty) {
      candidates.add(Directory(path));
    }
  }

  void addSideBySideCandidates(String? sdkPath) {
    if (sdkPath == null || sdkPath.isEmpty) {
      return;
    }
    final ndkBase = Directory(p.join(sdkPath, 'ndk'));
    if (!ndkBase.existsSync()) {
      return;
    }

    candidates.add(
      Directory(p.join(ndkBase.path, _preferredAndroidNdkVersion)),
    );

    final versions = ndkBase.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    candidates.addAll(versions);
  }

  addDirectory(androidNdkPath);
  addDirectory(Platform.environment['ANDROID_NDK_HOME']);
  addDirectory(Platform.environment['ANDROID_NDK']);

  addSideBySideCandidates(Platform.environment['ANDROID_HOME']);
  addSideBySideCandidates(Platform.environment['ANDROID_SDK_ROOT']);
  final home = Platform.environment['HOME'];
  addSideBySideCandidates(
    home == null ? null : p.join(home, 'Library', 'Android', 'sdk'),
  );
  addSideBySideCandidates(home == null ? null : p.join(home, 'Android', 'Sdk'));
  addSideBySideCandidates('/usr/local/android-sdk');
  addSideBySideCandidates('/opt/android-sdk');

  final seen = <String>{};
  for (final candidate in candidates) {
    final normalizedPath = p.normalize(candidate.path);
    if (!seen.add(normalizedPath)) {
      continue;
    }
    if (_isAndroidNdk(candidate)) {
      return candidate;
    }
  }

  return null;
}

bool _isAndroidNdk(Directory directory) {
  return File(
    p.join(directory.path, 'build', 'cmake', 'android.toolchain.cmake'),
  ).existsSync();
}

File? _findLibompInNdk(Directory ndkDirectory, String ompArch) {
  final prebuiltDir = Directory(
    p.join(ndkDirectory.path, 'toolchains', 'llvm', 'prebuilt'),
  );
  if (!prebuiltDir.existsSync()) {
    return null;
  }

  final files =
      prebuiltDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.basename(file.path) == 'libomp.so')
          .where((file) => _isLibompForArch(file, ompArch))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return files.firstOrNull;
}

bool _isLibompForArch(File file, String ompArch) {
  final parts = p.split(file.path);
  for (var index = 0; index < parts.length - 2; index++) {
    if (parts[index] == 'linux' &&
        parts[index + 1] == ompArch &&
        parts[index + 2] == 'libomp.so') {
      return true;
    }
  }
  return false;
}

FileSystemEntity? _findEntityNamed(Directory directory, String name) {
  if (!directory.existsSync()) {
    return null;
  }

  final directFile = File(p.join(directory.path, name));
  if (directFile.existsSync()) {
    return directFile;
  }

  final directDirectory = Directory(p.join(directory.path, name));
  if (directDirectory.existsSync()) {
    return directDirectory;
  }

  final matches =
      directory
          .listSync(recursive: true)
          .where((entity) => p.basename(entity.path) == name)
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return matches.firstOrNull;
}

/// Builds llama.cpp from source using CMake.
Future<List<Uri>?> _buildFromSource(
  OS targetOS,
  Architecture? targetArch,
  String libraryName,
  BuildInput input,
  Logger logger,
) async {
  if (targetArch == null) {
    logger.severe('Target architecture unknown, cannot build from source');
    return null;
  }

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
    // `app` is the unified `llama` binary. Unlike examples/tools/server it is
    // NOT gated behind LLAMA_BUILD_COMMON upstream, so it builds even with
    // everything else off and then fails on generated headers it never got
    // (`build-info.h`, `arg.h`). We only want the shared libraries.
    '-DLLAMA_BUILD_APP=OFF',
    // The `common` helper library only exists to serve examples/tools/app, all
    // of which are off. Skipping it saves a large chunk of build time.
    '-DLLAMA_BUILD_COMMON=OFF',
    // Embedded web UI for the server; defaults ON independently of
    // LLAMA_BUILD_SERVER and can reach out to Hugging Face for a prebuilt
    // bundle. Neither is wanted from inside a build hook.
    '-DLLAMA_BUILD_UI=OFF',
    '-DLLAMA_CURL=OFF',
    '-DBUILD_SHARED_LIBS=ON',
  ];

  String? androidNdkPath;
  if (targetOS == OS.android) {
    final abi = _getArchString(targetArch, targetOS);
    final ndkDirectory = _findAndroidNdk();
    if (ndkDirectory == null) {
      logger.severe('Android NDK not found');
      return null;
    }
    androidNdkPath = ndkDirectory.path;
    final androidToolchain = p.join(
      androidNdkPath,
      'build',
      'cmake',
      'android.toolchain.cmake',
    );

    cmakeArgs.addAll([
      '-DCMAKE_TOOLCHAIN_FILE=$androidToolchain',
      '-DANDROID_ABI=$abi',
      '-DANDROID_PLATFORM=android-28',
      '-DGGML_NATIVE=OFF',
      '-DGGML_LLAMAFILE=OFF',
      '-DGGML_BACKEND_DL=ON',
      '-DGGML_CPU_ALL_VARIANTS=${_androidCpuAllVariantsEnabled(abi) ? 'ON' : 'OFF'}',
      '-DGGML_CPU_KLEIDIAI=${abi == 'arm64-v8a' ? 'ON' : 'OFF'}',
      '-DGGML_OPENMP=${_androidOpenMpRequired(abi) ? 'ON' : 'OFF'}',
    ]);

    final vulkanEnabled = _androidVulkanEnabled(abi, logger);
    if (vulkanEnabled) {
      cmakeArgs.addAll(['-DGGML_VULKAN=ON', '-DGGML_VULKAN_RUN_TESTS=OFF']);
      logger.info(
        'Vulkan backend enabled for Android $abi. '
        'A host build of vulkan-shaders-gen will be produced as part of the build.',
      );
    } else {
      logger.info(
        'Vulkan backend disabled for Android $abi '
        '(set LLM_LLAMACPP_ANDROID_VULKAN=1 and ensure glslc is on PATH to enable).',
      );
    }
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

  if (targetOS == OS.android) {
    final abi = _getArchString(targetArch, targetOS);
    return _collectAndroidNativeLibraries(
      bundleDirectory: buildDir,
      outputDirectory: buildDir,
      abi: abi,
      openMpRequired: _androidOpenMpRequired(abi),
      androidNdkPath: androidNdkPath,
      logger: logger,
    );
  }

  return _collectNativeLibraries(
    targetOS: targetOS,
    targetArch: targetArch,
    libraryName: libraryName,
    bundleDirectory: buildDir,
    outputDirectory: buildDir,
    logger: logger,
  );
}

List<CodeAsset> codeAssetsForNativeLibrariesForTesting(
  Iterable<Uri> libraryPaths, {
  String packageName = 'llm_llamacpp',
}) {
  return [
    for (final libraryPath in libraryPaths)
      CodeAsset(
        package: packageName,
        name: _basename(libraryPath),
        linkMode: DynamicLoadingBundled(),
        file: libraryPath,
      ),
  ];
}

void _addCodeAssets(
  BuildOutputBuilder output,
  Iterable<Uri> libraryPaths,
  BuildInput input,
) {
  for (final asset in codeAssetsForNativeLibrariesForTesting(
    libraryPaths,
    packageName: input.packageName,
  )) {
    output.assets.code.add(asset);
  }
}

String _basename(Uri uri) {
  return uri.pathSegments.where((segment) => segment.isNotEmpty).last;
}
