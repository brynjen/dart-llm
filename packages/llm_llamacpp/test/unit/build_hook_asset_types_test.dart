import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  group('Build hook asset types', () {
    test('emits no assets when code assets are not requested', () async {
      // `extensions: []` leaves `buildAssetTypes` empty, which is what a
      // non-code-asset invocation looks like -- the shape that made
      // `flutter run -d macos --debug` fail with "Bad state: HookConfig.code
      // should only be accessed when building code assets". The hook must bail
      // out cleanly instead of throwing.
      await testBuildHook(
        mainMethod: hook.main,
        extensions: const <ProtocolExtension>[],
        check: (input, output) {
          expect(input.config.buildCodeAssets, isFalse);
          expect(output.assets.encodedAssets, isEmpty);
        },
      );
    });
  });
}
