import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../hook/build.dart';

void main() {
  group('ABI fingerprint', () {
    test('is stable for identical content', () {
      final dir = _makePackage({'lib/abi.dart': 'class Foo {}\n'});
      addTearDown(() => dir.deleteSync(recursive: true));

      final a = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      final b = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      expect(a, equals(b));
      expect(a, hasLength(12));
      expect(a, matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('changes when binding contents change', () {
      final dir = _makePackage({'lib/abi.dart': 'class Foo {}\n'});
      addTearDown(() => dir.deleteSync(recursive: true));

      final a = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      File(
        p.join(dir.path, 'lib', 'abi.dart'),
      ).writeAsStringSync('class Foo {} class Bar {}\n');
      final b = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      expect(a, isNot(equals(b)));
    });

    test('is invariant to CR (line ending differences across OSes)', () {
      final dirLf = _makePackage({'lib/abi.dart': 'a\nb\nc\n'});
      addTearDown(() => dirLf.deleteSync(recursive: true));
      final dirCrlf = _makePackage({'lib/abi.dart': 'a\r\nb\r\nc\r\n'});
      addTearDown(() => dirCrlf.deleteSync(recursive: true));

      final lf = computeAbiFingerprintForTesting(
        packageRoot: dirLf.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      final crlf = computeAbiFingerprintForTesting(
        packageRoot: dirCrlf.uri,
        relativeInputs: const ['lib/abi.dart'],
      );
      expect(lf, equals(crlf));
    });

    test('changes when ordering of inputs changes', () {
      final dir = _makePackage({
        'lib/a.dart': 'class A {}\n',
        'lib/b.dart': 'class B {}\n',
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      final ab = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/a.dart', 'lib/b.dart'],
      );
      final ba = computeAbiFingerprintForTesting(
        packageRoot: dir.uri,
        relativeInputs: const ['lib/b.dart', 'lib/a.dart'],
      );
      expect(ab, isNot(equals(ba)));
    });

    test('throws a clear error when an input is missing', () {
      final dir = Directory.systemTemp.createTempSync('llm_llamacpp_abi_');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(
        () => computeAbiFingerprintForTesting(
          packageRoot: dir.uri,
          relativeInputs: const ['lib/missing.dart'],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('ABI fingerprint input not found'),
          ),
        ),
      );
    });
  });
}

Directory _makePackage(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('llm_llamacpp_abi_');
  files.forEach((relative, contents) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return dir;
}
