import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/build.dart';

/// `ggml-vulkan` does `find_package(SPIRV-Headers CONFIG REQUIRED)`, and the
/// Android NDK toolchain sets `CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY`, so a
/// host install is invisible unless the build hook points CMake straight at the
/// config directory. Finding it is therefore both the gate for enabling Vulkan
/// and the value passed to CMake — if it silently returns null on a machine
/// that does have the headers, Android builds lose GPU offload for no reason.
void main() {
  group('SPIRV-Headers locator', () {
    test('finds the config nested in a SPIRV-Headers subdirectory', () {
      // The layout Debian/Ubuntu's `spirv-headers` package installs.
      final root = _tempDir();
      final configDir = Directory(p.join(root.path, 'SPIRV-Headers'))
        ..createSync();
      File(
        p.join(configDir.path, 'SPIRV-HeadersConfig.cmake'),
      ).writeAsStringSync('');

      expect(
        findSpirvHeadersConfigDirForTesting(searchRoots: [root.path]),
        equals(configDir.path),
      );
    });

    test('finds a config sitting directly in a search root', () {
      final root = _tempDir();
      File(
        p.join(root.path, 'spirv-headers-config.cmake'),
      ).writeAsStringSync('');

      expect(
        findSpirvHeadersConfigDirForTesting(searchRoots: [root.path]),
        equals(root.path),
      );
    });

    test('accepts the lowercase config filename', () {
      final root = _tempDir();
      final configDir = Directory(p.join(root.path, 'SPIRV-Headers'))
        ..createSync();
      File(
        p.join(configDir.path, 'spirv-headers-config.cmake'),
      ).writeAsStringSync('');

      expect(
        findSpirvHeadersConfigDirForTesting(searchRoots: [root.path]),
        equals(configDir.path),
      );
    });

    test('skips roots that do not exist and keeps looking', () {
      final root = _tempDir();
      final configDir = Directory(p.join(root.path, 'SPIRV-Headers'))
        ..createSync();
      File(
        p.join(configDir.path, 'SPIRV-HeadersConfig.cmake'),
      ).writeAsStringSync('');

      expect(
        findSpirvHeadersConfigDirForTesting(
          searchRoots: ['/definitely/not/here', root.path],
        ),
        equals(configDir.path),
      );
    });

    test('returns null when nothing is installed', () {
      // Must be null, not a throw: the caller downgrades to a CPU-only build.
      expect(
        findSpirvHeadersConfigDirForTesting(searchRoots: [_tempDir().path]),
        isNull,
      );
    });

    test('an explicit directory wins over the search roots', () {
      final explicit = _tempDir();
      File(
        p.join(explicit.path, 'SPIRV-HeadersConfig.cmake'),
      ).writeAsStringSync('');

      final root = _tempDir();
      final decoy = Directory(p.join(root.path, 'SPIRV-Headers'))..createSync();
      File(
        p.join(decoy.path, 'SPIRV-HeadersConfig.cmake'),
      ).writeAsStringSync('');

      expect(
        findSpirvHeadersConfigDirForTesting(
          searchRoots: [root.path],
          explicitDir: explicit.path,
        ),
        equals(explicit.path),
      );
    });

    test('an explicit directory that does not exist yields null', () {
      expect(
        findSpirvHeadersConfigDirForTesting(
          searchRoots: const [],
          explicitDir: '/definitely/not/here',
        ),
        isNull,
      );
    });
  });
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('spirv_headers');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
