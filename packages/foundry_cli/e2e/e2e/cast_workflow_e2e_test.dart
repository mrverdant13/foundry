import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry cast and recast', () {
    late Directory workDir;
    late String moldPath;
    late Directory expectedDirectory;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('foundry_cli_cast_e2e_');
      moldPath = fixturePath('cast_pipeline_mold');
      expectedDirectory = Directory(fixturePath('cast_pipeline/expected'));
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'casts a fixture mold and recasts from persisted state',
      () async {
        const vars = {'project_name': 'my project'};

        final castResult = await runFoundry(
          ['cast', moldPath, '--output=out'],
          workingDirectory: workDir.path,
          e2eVars: vars,
        );

        expect(castResult.exitCode, 0, reason: castResult.stderr);
        expect(castResult.stdout, contains('Cast completed'));
        expect(castResult.stdout, contains('artifacts generated'));

        final outputDirectory = Directory(p.join(workDir.path, 'out'));
        expectDirectoryTreesMatch(
          expected: expectedDirectory,
          actual: outputDirectory,
        );

        final stateFile = File(
          p.join(workDir.path, '.foundry', 'last_cast.json'),
        );
        expect(stateFile.existsSync(), isTrue);
        final state =
            json.decode(stateFile.readAsStringSync()) as Map<String, Object?>;
        expect(state['moldPath'], moldPath);
        expect(state['outputPath'], 'out');
        expect((state['vars']! as Map)['project_name'], 'my project');

        await File(p.join(outputDirectory.path, 'cast_complete.txt')).delete();
        await File(p.join(outputDirectory.path, 'README.md')).writeAsString(
          '# stale\n',
        );

        final recastResult = await runFoundry(
          ['recast', '--force'],
          workingDirectory: workDir.path,
        );

        expect(recastResult.exitCode, 0, reason: recastResult.stderr);
        expect(recastResult.stdout, contains('Recast completed'));
        expectDirectoryTreesMatch(
          expected: expectedDirectory,
          actual: outputDirectory,
        );
      },
      tags: const ['e2e'],
      // Cast + recast each spawn the CLI, run pub get, and load variables in
      // an isolate — well over the default 30s on cold CI runners.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
