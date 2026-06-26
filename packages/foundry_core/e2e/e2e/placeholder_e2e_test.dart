import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'foundry_core version is exposed',
    () {
      expect(foundryCoreVersion, isNotEmpty);
    },
    tags: const ['e2e'],
  );
}
