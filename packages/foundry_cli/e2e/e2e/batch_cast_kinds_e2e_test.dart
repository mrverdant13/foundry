import 'dart:convert';
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
            '--skip-hooks=prepare',
            '--skip-hooks=shape',
            '--skip-hooks=finish',
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

        final stateFile = File(
          p.join(workDir.path, '.foundry', 'last_cast.json'),
        );
        expect(stateFile.existsSync(), isTrue);
        final state =
            json.decode(stateFile.readAsStringSync()) as Map<String, Object?>;
        expect(state['moldPath'], moldPath);
        expect(state['outputPath'], 'out');
        final vars = state['vars']! as Map<String, dynamic>;
        expect(vars['project_name'], 'BatchDemo');
        expect(vars['use_null_safety'], isTrue);
        expect(vars['port'], 8080);
        expect(vars['scale'], 1.5);
        expect(vars['project_type'], 'package');
        expect(vars['platforms'], ['android', 'web']);
      },
      tags: const ['e2e'],
      // Spawns the CLI, materializes a synthetic session helper, and runs
      // dart pub get — well over the default 30s on cold CI runners.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
