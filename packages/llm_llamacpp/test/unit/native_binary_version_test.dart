import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/build.dart';

/// The prebuilt bundle the hook downloads is named after a GitHub release, and
/// that name has to match the package version — otherwise a published package
/// requests assets from a release that was never cut and, because the published
/// archive carries no `llamacpp/` source, fails hard instead of falling back.
///
/// Two independent readers of the same `version:` field have to agree: this hook
/// and the `Resolve version` step in `.github/workflows/build-release.yaml`.
/// These tests pin the hook's half and the shape both rely on.
void main() {
  group('native binary version', () {
    test('is the version from this package pubspec', () {
      final packageRoot = _packageRoot();
      final version = readNativeBinaryVersionForTesting(packageRoot);

      final declared = _pubspecVersionViaWorkflowRegex(
        File.fromUri(packageRoot.resolve('pubspec.yaml')),
      );

      expect(
        version,
        equals(declared),
        reason:
            'hook/build.dart must request prebuilts for the package version. '
            'Bump both together, and cut a matching release tagged $declared.',
      );
    });

    test('is read from the pubspec, not hardcoded', () {
      final dir = _makePackage('version: 9.9.9-test\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(readNativeBinaryVersionForTesting(dir.uri), equals('9.9.9-test'));
    });

    test('ignores nested and commented version keys', () {
      final dir = _makePackage('''
name: fake
# version: 0.0.1
version: 1.2.3
environment:
  sdk: ^3.12.0
dependencies:
  some_package:
    version: 4.5.6
''');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(readNativeBinaryVersionForTesting(dir.uri), equals('1.2.3'));
    });

    test('falls back rather than throwing when the pubspec is unreadable', () {
      final dir = Directory.systemTemp.createTempSync('no_pubspec');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(
        readNativeBinaryVersionForTesting(dir.uri),
        matches(RegExp(r'^\d+\.\d+\.\d+')),
      );
    });
  });
}

Uri _packageRoot() {
  // Tests run with the package as CWD.
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not locate the llm_llamacpp package root from ${dir.path}');
    }
    dir = parent;
  }
  return dir.uri;
}

/// Mirrors the `sed` expression in the workflow's `Resolve version` step, so a
/// change to the pubspec that breaks one reader breaks this test too.
String _pubspecVersionViaWorkflowRegex(File pubspec) {
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  fail('No top-level `version:` in ${pubspec.path}');
}

Directory _makePackage(String pubspecContents) {
  final dir = Directory.systemTemp.createTempSync('fake_package');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspecContents);
  return dir;
}
