import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/local_foundry_core.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry pattern init → mold derive → inspect → sync', () {
    late Directory workDir;
    late Directory patternDir;
    late Directory moldDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp(
        'foundry_cli_pattern_derive_sync_e2e_',
      );
      patternDir = Directory(p.join(workDir.path, 'pattern'))..createSync();
      moldDir = Directory(p.join(workDir.path, 'mold'));
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'scaffolds a local pattern, derives a mold, inspects it, then syncs',
      () async {
        final initResult = await runFoundry(
          ['pattern', 'init', '--name=demo_pattern'],
          workingDirectory: patternDir.path,
        );
        expect(initResult.exitCode, 0, reason: initResult.stderr);
        expect(initResult.stdout, contains('demo_pattern'));
        expect(
          File(p.join(patternDir.path, '.foundry', 'pattern.yaml'))
              .existsSync(),
          isTrue,
        );

        // Seed pattern content beyond the init scaffold so derive/sync have
        // real template files to liquidize and refresh.
        await File(p.join(patternDir.path, 'lib', 'app.dart'))
            .create(recursive: true)
            .then(
              (file) => file.writeAsString(
                'void main() {\n'
                "  print('Hello {{ project_name }}');\n"
                '}\n',
              ),
            );
        // Matches starter ignore globs from `pattern init` (`build/**`).
        await File(p.join(patternDir.path, 'build', 'out.txt'))
            .create(recursive: true)
            .then((file) => file.writeAsString('ignored'));

        final deriveResult = await runFoundry(
          [
            'mold',
            'derive',
            '--pattern=${patternDir.path}',
            '--output=${moldDir.path}',
          ],
          workingDirectory: workDir.path,
        );
        expect(deriveResult.exitCode, 0, reason: deriveResult.stderr);
        expect(deriveResult.stdout, contains('Derived mold'));
        expect(File(p.join(moldDir.path, 'pubspec.yaml')).existsSync(), isTrue);
        expect(
          File(p.join(moldDir.path, 'variables.dart')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(moldDir.path, 'template', 'lib', 'app.dart'))
              .existsSync(),
          isTrue,
        );
        expect(
          File(p.join(moldDir.path, 'template', 'build', 'out.txt'))
              .existsSync(),
          isFalse,
        );

        // Hosted foundry_core would require network; pin the local package.
        await useLocalFoundryCore(moldDir);

        final inspectResult = await runFoundry(
          ['mold', 'inspect', moldDir.path],
          workingDirectory: workDir.path,
        );
        expect(inspectResult.exitCode, 0, reason: inspectResult.stderr);
        expect(inspectResult.stdout, contains('is valid'));
        expect(inspectResult.stdout, contains('demo_pattern'));

        final variablesPath = p.join(moldDir.path, 'variables.dart');
        const customVariables = '''
// custom author edits
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''';
        await File(variablesPath).writeAsString(customVariables);

        await File(p.join(patternDir.path, 'README.md')).writeAsString(
          '# demo_pattern\n\nUpdated for sync {{ project_name }}\n',
        );
        await File(p.join(patternDir.path, 'lib', 'new_file.dart'))
            .create(recursive: true)
            .then((file) => file.writeAsString('class NewFile {}\n'));

        final syncResult = await runFoundry(
          ['mold', 'sync', '--pattern=${patternDir.path}'],
          workingDirectory: moldDir.path,
        );
        expect(syncResult.exitCode, 0, reason: syncResult.stderr);
        expect(syncResult.stdout, contains('Synced mold'));
        expect(File(variablesPath).readAsStringSync(), customVariables);
        expect(
          File(p.join(moldDir.path, 'template', 'README.md'))
              .readAsStringSync(),
          contains('Updated for sync'),
        );
        expect(
          File(
            p.join(moldDir.path, 'template', 'lib', 'new_file.dart'),
          ).existsSync(),
          isTrue,
        );
      },
      tags: const ['e2e'],
      // Spawns the CLI several times and runs pub get for mold inspect.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
