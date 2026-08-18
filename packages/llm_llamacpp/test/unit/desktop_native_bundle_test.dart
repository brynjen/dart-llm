import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/build.dart';

void main() {
  group('Desktop native bundle hook', () {
    test('macOS emits the ggml libraries built alongside libllama', () async {
      final bundle = _tempBundle('macos');
      // A `-DBUILD_SHARED_LIBS=ON` macOS tree: unversioned symlinks pointing at
      // versioned real files, which is what CMake actually leaves behind.
      _createVersionedMacOSLibrary(bundle, 'libllama');
      _createVersionedMacOSLibrary(bundle, 'libggml');
      _createVersionedMacOSLibrary(bundle, 'libggml-base');
      _createVersionedMacOSLibrary(bundle, 'libggml-cpu');
      _createVersionedMacOSLibrary(bundle, 'libggml-metal');
      _createVersionedMacOSLibrary(bundle, 'libggml-blas');

      final libraries = await collectDesktopNativeLibrariesForTesting(
        targetOS: OS.macOS,
        bundleDirectory: bundle.uri,
        libraryName: 'libllama.dylib',
      );

      // Primary, core ggml, CPU backend, then remaining backends sorted.
      expect(_libraryNames(libraries), [
        'libllama.dylib',
        'libggml.dylib',
        'libggml-base.dylib',
        'libggml-cpu.dylib',
        'libggml-blas.dylib',
        'libggml-metal.dylib',
      ]);
    });

    test('macOS skips the versioned aliases of the same binary', () async {
      final bundle = _tempBundle('macos_versioned');
      _createVersionedMacOSLibrary(bundle, 'libllama');
      _createVersionedMacOSLibrary(bundle, 'libggml');
      _createVersionedMacOSLibrary(bundle, 'libggml-base');
      _createVersionedMacOSLibrary(bundle, 'libggml-cpu');

      final libraries = await collectDesktopNativeLibrariesForTesting(
        targetOS: OS.macOS,
        bundleDirectory: bundle.uri,
        libraryName: 'libllama.dylib',
      );

      // `libggml.0.dylib` / `libggml.0.20.1.dylib` are aliases of
      // `libggml.dylib`; bundling them would ship the same binary three times.
      expect(
        _libraryNames(libraries).where((name) => name.contains('.0.')),
        isEmpty,
      );
      expect(_libraryNames(libraries), hasLength(4));
    });

    test(
      'Linux emits ggml under its soname, primary under its plain name',
      () async {
        final bundle = _tempBundle('linux');
        for (final stem in [
          'libllama',
          'libggml',
          'libggml-base',
          'libggml-cpu-z',
          'libggml-cpu-a',
          'libggml-cuda',
        ]) {
          _createFile(bundle, '$stem.so');
          _createFile(bundle, '$stem.so.0');
          _createFile(bundle, '$stem.so.0.20.1');
        }

        final libraries = await collectDesktopNativeLibrariesForTesting(
          targetOS: OS.linux,
          bundleDirectory: bundle.uri,
          libraryName: 'libllama.so',
        );

        // Dependencies are recorded in DT_NEEDED by soname (`libggml.so.0`), so
        // that is the name that has to be shipped. The primary library keeps its
        // plain name because the loader dlopens it by that name.
        expect(_libraryNames(libraries), [
          'libllama.so',
          'libggml.so.0',
          'libggml-base.so.0',
          'libggml-cpu-a.so.0',
          'libggml-cpu-z.so.0',
          'libggml-cuda.so.0',
        ]);
      },
    );

    test(
      'Linux falls back to the plain name when no soname alias exists',
      () async {
        final bundle = _tempBundle('linux_unversioned');
        for (final name in [
          'libllama.so',
          'libggml.so',
          'libggml-base.so',
          'libggml-cpu.so',
        ]) {
          _createFile(bundle, name);
        }

        final libraries = await collectDesktopNativeLibrariesForTesting(
          targetOS: OS.linux,
          bundleDirectory: bundle.uri,
          libraryName: 'libllama.so',
        );

        expect(_libraryNames(libraries), [
          'libllama.so',
          'libggml.so',
          'libggml-base.so',
          'libggml-cpu.so',
        ]);
      },
    );

    test('Windows collects the prefix-less DLL names', () async {
      final bundle = _tempBundle('windows');
      for (final name in [
        'llama.dll',
        'ggml.dll',
        'ggml-base.dll',
        'ggml-cpu.dll',
        'ggml-vulkan.dll',
      ]) {
        _createFile(bundle, name);
      }

      final libraries = await collectDesktopNativeLibrariesForTesting(
        targetOS: OS.windows,
        bundleDirectory: bundle.uri,
        libraryName: 'llama.dll',
      );

      expect(_libraryNames(libraries), [
        'llama.dll',
        'ggml.dll',
        'ggml-base.dll',
        'ggml-cpu.dll',
        'ggml-vulkan.dll',
      ]);
    });

    test('throws when a required ggml library is absent', () async {
      final bundle = _tempBundle('incomplete');
      _createFile(bundle, 'libllama.dylib');
      _createFile(bundle, 'libggml.dylib');
      _createFile(bundle, 'libggml-cpu.dylib');

      await expectLater(
        collectDesktopNativeLibrariesForTesting(
          targetOS: OS.macOS,
          bundleDirectory: bundle.uri,
          libraryName: 'libllama.dylib',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('libggml-base.dylib'),
          ),
        ),
      );
    });

    test('throws when no CPU backend was built', () async {
      final bundle = _tempBundle('no_cpu');
      _createFile(bundle, 'libllama.dylib');
      _createFile(bundle, 'libggml.dylib');
      _createFile(bundle, 'libggml-base.dylib');

      await expectLater(
        collectDesktopNativeLibrariesForTesting(
          targetOS: OS.macOS,
          bundleDirectory: bundle.uri,
          libraryName: 'libllama.dylib',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('libggml-cpu*.dylib'),
          ),
        ),
      );
    });

    test('emits one code asset per collected library', () async {
      final bundle = _tempBundle('assets');
      for (final name in [
        'libllama.dylib',
        'libggml.dylib',
        'libggml-base.dylib',
        'libggml-cpu.dylib',
      ]) {
        _createFile(bundle, name);
      }

      final libraries = await collectDesktopNativeLibrariesForTesting(
        targetOS: OS.macOS,
        bundleDirectory: bundle.uri,
        libraryName: 'libllama.dylib',
      );
      final assets = codeAssetsForNativeLibrariesForTesting(libraries);

      expect(assets.map((asset) => asset.id), [
        'package:llm_llamacpp/libllama.dylib',
        'package:llm_llamacpp/libggml.dylib',
        'package:llm_llamacpp/libggml-base.dylib',
        'package:llm_llamacpp/libggml-cpu.dylib',
      ]);
    });
  });
}

Directory _tempBundle(String label) {
  final temp = Directory.systemTemp.createTempSync(
    'llm_llamacpp_desktop_${label}_',
  );
  addTearDown(() => temp.deleteSync(recursive: true));
  final bundle = Directory(p.join(temp.path, 'bundle'))
    ..createSync(recursive: true);
  return bundle;
}

void _createFile(Directory directory, String name) {
  File(p.join(directory.path, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(name);
}

/// Mirrors CMake's macOS layout: `libX.dylib` -> `libX.0.dylib` ->
/// `libX.0.20.1.dylib`, where only the last one is a real file.
void _createVersionedMacOSLibrary(Directory directory, String stem) {
  _createFile(directory, '$stem.0.20.1.dylib');
  Link(
    p.join(directory.path, '$stem.0.dylib'),
  ).createSync('$stem.0.20.1.dylib');
  Link(p.join(directory.path, '$stem.dylib')).createSync('$stem.0.dylib');
}

List<String> _libraryNames(List<Uri> libraries) =>
    libraries.map((uri) => p.basename(uri.toFilePath())).toList();
