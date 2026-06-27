import 'package:foundry_cli/src/version.dart';
import 'package:test/test.dart';

void main() {
  test(
    'foundry_cli version is exposed',
    () {
      expect(foundryCliVersion, isNotEmpty);
    },
    tags: const ['e2e'],
  );
}
