import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry cast --vars-file with scalar and choice kinds', () {
    late Directory workDir;
    late String moldPath;
    late String varsFilePath;
    late Directory expectedDirectory;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp(
        'foundry_cli_batch_cast_e2e_',
      );
      moldPath = fixturePath('batch_cast_kinds_mold');
      varsFilePath = fixturePath('batch_cast_kinds/vars.json');
      expectedDirectory = Directory(fixturePath('batch_cast_kinds/expected'));
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'casts successfully with --vars-file and skips the TUI',
      () async {
        final castResult = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out',
            '--vars-file=$varsFilePath',
            '--no-hooks',
          ],
          workingDirectory: workDir.path,
        );

        expect(castResult.exitCode, 0, reason: castResult.stderr);
        expect(castResult.stdout, contains('Cast completed'));
        expect(castResult.stdout, contains('artifacts generated'));

        expectDirectoryTreesMatch(
          expected: expectedDirectory,
          actual: Directory(p.join(workDir.path, 'out')),
        );
      },
      tags: const ['e2e'],
      // Spawns the CLI, runs pub get on the fixture mold, and loads variables
      // in an isolate — well over the default 30s on cold CI runners.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
