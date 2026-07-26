import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry cast --vars-file with live visibility/defaults/validators',
      () {
    late Directory workDir;
    late String moldPath;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp(
        'foundry_cli_batch_live_callbacks_e2e_',
      );
      moldPath = fixturePath('batch_cast_live_callbacks_mold');
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'applies live defaultValue and visibleWhen for package vs app',
      () async {
        final packageVars = fixturePath(
          'batch_cast_live_callbacks/vars_package.json',
        );
        final packageResult = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out_package',
            '--vars-file=$packageVars',
          ],
          workingDirectory: workDir.path,
        );

        expect(packageResult.exitCode, 0, reason: packageResult.stderr);
        expect(packageResult.stdout, contains('Cast completed'));
        expectDirectoryTreesMatch(
          expected: Directory(
            fixturePath('batch_cast_live_callbacks/expected_package'),
          ),
          actual: Directory(p.join(workDir.path, 'out_package')),
        );

        final stateFile = File(
          p.join(workDir.path, '.foundry', 'last_cast.json'),
        );
        expect(stateFile.existsSync(), isTrue);
        final state =
            json.decode(stateFile.readAsStringSync()) as Map<String, Object?>;
        expect(state['moldPath'], moldPath);
        expect(state['outputPath'], 'out_package');
        final vars = state['vars']! as Map<String, dynamic>;
        expect(vars['project_type'], 'package');
        expect(vars['project_name'], 'MyApp');
        expect(vars['package_name'], 'myapp');
        expect(vars['shaped'], 'yes');

        final appVars = fixturePath('batch_cast_live_callbacks/vars_app.json');
        final appResult = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out_app',
            '--force',
            '--vars-file=$appVars',
          ],
          workingDirectory: workDir.path,
        );

        expect(appResult.exitCode, 0, reason: appResult.stderr);
        expectDirectoryTreesMatch(
          expected: Directory(
            fixturePath('batch_cast_live_callbacks/expected_app'),
          ),
          actual: Directory(p.join(workDir.path, 'out_app')),
        );

        final appState =
            json.decode(stateFile.readAsStringSync()) as Map<String, Object?>;
        final appVarsMap = appState['vars']! as Map<String, dynamic>;
        expect(appVarsMap['project_type'], 'app');
        expect(appVarsMap.containsKey('package_name'), isFalse);
      },
      tags: const ['e2e'],
      // Spawns the CLI twice; each launch materializes a synthetic helper
      // package and runs dart pub get — well over the default 30s on cold CI.
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'rejects values that fail live field validators',
      () async {
        final invalidVars = fixturePath(
          'batch_cast_live_callbacks/vars_invalid.json',
        );
        final result = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out_invalid',
            '--vars-file=$invalidVars',
          ],
          workingDirectory: workDir.path,
        );

        expect(result.exitCode, 1, reason: result.stdout + result.stderr);
        expect(
          '${result.stdout}${result.stderr}',
          contains('project_name must not contain spaces'),
        );
        expect(
          File(p.join(workDir.path, '.foundry', 'last_cast.json')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(workDir.path, 'out_invalid', 'README.md')).existsSync(),
          isFalse,
        );
      },
      tags: const ['e2e'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'honors live defaults via --vars flag form',
      () async {
        final result = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out_flag',
            '--vars=project_type=package,project_name=FlagApp',
          ],
          workingDirectory: workDir.path,
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          await File(
            p.join(workDir.path, 'out_flag', 'README.md'),
          ).readAsString(),
          'type=package\n'
          'name=FlagApp\n'
          'package=flagapp\n'
          'shaped=yes\n',
        );
      },
      tags: const ['e2e'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
