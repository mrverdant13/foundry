import 'package:foundry_cli/src/version.dart';
import 'package:test/test.dart';

import 'helpers/run_foundry.dart';

void main() {
  test(
    'foundry --version prints the package version',
    () async {
      final result = await runFoundry(
        ['--version'],
        workingDirectory: '.',
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout.trim(), foundryCliVersion);
    },
    tags: const ['e2e'],
  );
}
