import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/build.dart';

void main() {
  group('Android native bundle hook', () {
    test(
      'emits core libraries, sorted CPU backends, and bundled libomp',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'llm_llamacpp_android_bundle_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));

        final bundle = Directory(p.join(temp.path, 'bundle'));
        _createSharedLibrary(bundle, 'libllama.so');
        _createSharedLibrary(bundle, 'libggml.so');
        _createSharedLibrary(bundle, 'libggml-base.so');
        _createSharedLibrary(bundle, 'libggml-cpu-z.so');
        _createSharedLibrary(bundle, 'libggml-cpu-a.so');
        _createSharedLibrary(bundle, 'libomp.so');

        final libraries = await collectAndroidNativeLibrariesForTesting(
          bundleDirectory: bundle.uri,
          outputDirectory: bundle.uri,
          abi: 'arm64-v8a',
          openMpRequired: true,
        );

        expect(_libraryNames(libraries), [
          'libllama.so',
          'libggml.so',
          'libggml-base.so',
          'libggml-cpu-a.so',
          'libggml-cpu-z.so',
          'libomp.so',
        ]);

        final assets = codeAssetsForNativeLibrariesForTesting(libraries);
        expect(assets.map((asset) => asset.id), [
          'package:llm_llamacpp/libllama.so',
          'package:llm_llamacpp/libggml.so',
          'package:llm_llamacpp/libggml-base.so',
          'package:llm_llamacpp/libggml-cpu-a.so',
          'package:llm_llamacpp/libggml-cpu-z.so',
          'package:llm_llamacpp/libomp.so',
        ]);
      },
    );

    test(
      'includes optional libggml-vulkan.so when present in the bundle',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'llm_llamacpp_android_bundle_vulkan_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));

        final bundle = Directory(p.join(temp.path, 'bundle'));
        _createSharedLibrary(bundle, 'libllama.so');
        _createSharedLibrary(bundle, 'libggml.so');
        _createSharedLibrary(bundle, 'libggml-base.so');
        _createSharedLibrary(bundle, 'libggml-cpu-a.so');
        _createSharedLibrary(bundle, 'libggml-vulkan.so');

        final libraries = await collectAndroidNativeLibrariesForTesting(
          bundleDirectory: bundle.uri,
          outputDirectory: bundle.uri,
          abi: 'arm64-v8a',
          openMpRequired: false,
        );

        expect(_libraryNames(libraries), [
          'libllama.so',
          'libggml.so',
          'libggml-base.so',
          'libggml-cpu-a.so',
          'libggml-vulkan.so',
        ]);
      },
    );

    test('fails clearly when a core library is missing', () async {
      final temp = Directory.systemTemp.createTempSync(
        'llm_llamacpp_android_missing_core_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      final bundle = Directory(p.join(temp.path, 'bundle'));
      _createSharedLibrary(bundle, 'libllama.so');
      _createSharedLibrary(bundle, 'libggml-base.so');
      _createSharedLibrary(bundle, 'libggml-cpu-a.so');

      expect(
        () => collectAndroidNativeLibrariesForTesting(
          bundleDirectory: bundle.uri,
          outputDirectory: bundle.uri,
          abi: 'x86_64',
          openMpRequired: false,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('libggml.so'),
          ),
        ),
      );
    });

    test('fails clearly when CPU backend libraries are missing', () async {
      final temp = Directory.systemTemp.createTempSync(
        'llm_llamacpp_android_missing_cpu_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      final bundle = Directory(p.join(temp.path, 'bundle'));
      _createSharedLibrary(bundle, 'libllama.so');
      _createSharedLibrary(bundle, 'libggml.so');
      _createSharedLibrary(bundle, 'libggml-base.so');

      expect(
        () => collectAndroidNativeLibrariesForTesting(
          bundleDirectory: bundle.uri,
          outputDirectory: bundle.uri,
          abi: 'x86_64',
          openMpRequired: false,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('libggml-cpu*.so'),
          ),
        ),
      );
    });

    const abiToOpenMpArch = {
      'arm64-v8a': 'aarch64',
      'armeabi-v7a': 'arm',
      'x86_64': 'x86_64',
      'x86': 'i386',
    };

    for (final entry in abiToOpenMpArch.entries) {
      test('copies libomp.so from fake NDK for ${entry.key}', () async {
        final temp = Directory.systemTemp.createTempSync(
          'llm_llamacpp_android_omp_${entry.key}_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));

        final bundle = Directory(p.join(temp.path, 'bundle'));
        _createSharedLibrary(bundle, 'libllama.so');
        _createSharedLibrary(bundle, 'libggml.so');
        _createSharedLibrary(bundle, 'libggml-base.so');
        _createSharedLibrary(bundle, 'libggml-cpu-a.so');

        final output = Directory(p.join(temp.path, 'output'));
        final ndk = _createFakeNdk(temp, entry.value);

        final libraries = await collectAndroidNativeLibrariesForTesting(
          bundleDirectory: bundle.uri,
          outputDirectory: output.uri,
          abi: entry.key,
          openMpRequired: true,
          androidNdkPath: ndk.path,
        );

        final copiedOpenMp = File(p.join(output.path, 'libomp.so'));
        expect(copiedOpenMp.existsSync(), isTrue);
        expect(copiedOpenMp.readAsStringSync(), 'libomp-${entry.value}');
        expect(_libraryNames(libraries), contains('libomp.so'));
      });
    }
  });
}

void _createSharedLibrary(Directory directory, String name) {
  final file = File(p.join(directory.path, name));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(name);
}

Directory _createFakeNdk(Directory temp, String openMpArch) {
  final ndk = Directory(p.join(temp.path, 'fake_ndk'));
  File(
    p.join(ndk.path, 'build', 'cmake', 'android.toolchain.cmake'),
  ).createSync(recursive: true);

  final libomp = File(
    p.join(
      ndk.path,
      'toolchains',
      'llvm',
      'prebuilt',
      'test-host',
      'lib',
      'clang',
      '17',
      'lib',
      'linux',
      openMpArch,
      'libomp.so',
    ),
  );
  libomp.parent.createSync(recursive: true);
  libomp.writeAsStringSync('libomp-$openMpArch');

  return ndk;
}

List<String> _libraryNames(Iterable<Uri> libraries) {
  return [for (final library in libraries) p.basename(library.toFilePath())];
}
