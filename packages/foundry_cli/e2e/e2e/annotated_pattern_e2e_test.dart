import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';
import 'helpers/local_foundry_core.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry annotated pattern derive → sync → cast', () {
    late Directory workDir;
    late Directory patternDir;
    late Directory moldDir;
    late Directory expectedDirectory;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp(
        'foundry_cli_annotated_pattern_e2e_',
      );
      patternDir = Directory(p.join(workDir.path, 'pattern'));
      moldDir = Directory(p.join(workDir.path, 'mold'));
      expectedDirectory = Directory(
        fixturePath('annotated_pattern_cast/expected'),
      );

      await _copyDirectory(
        Directory(fixturePath('annotated_pattern')),
        patternDir,
      );
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'derives, syncs, and casts an annotated pattern with --vars',
      () async {
        // Matches starter ignore globs; must not appear under template/.
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

        expect(
          File(
            p.join(moldDir.path, 'template', 'lib', '{{ package_name }}.dart'),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(moldDir.path, 'template', 'build', 'out.txt'))
              .existsSync(),
          isFalse,
        );
        expect(
          File(
            p.join(moldDir.path, 'template', 'lib', '{{ package_name }}.dart'),
          ).readAsStringSync(),
          contains("stdout.writeln('Hello from {{ package_name }}')"),
        );

        // Hosted foundry_core would require network; pin the local package.
        await useLocalFoundryCore(moldDir);

        const customVariables = '''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'package_name': FoundryStringVariable(label: 'Package name'),
  },
);
''';
        final variablesPath = p.join(moldDir.path, 'variables.dart');
        await File(variablesPath).writeAsString(customVariables);

        await File(p.join(patternDir.path, 'README.md')).writeAsString(
          '# ref_pkg\n'
          '\n'
          'Sample annotated pattern for derive, sync, and cast.\n'
          '\n'
          'Synced for ref_pkg.\n',
        );
        await File(p.join(patternDir.path, 'lib', 'extra.txt'))
            .create(recursive: true)
            .then((file) => file.writeAsString('extra for ref_pkg\n'));

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
          contains('Synced for {{ package_name }}'),
        );
        expect(
          File(p.join(moldDir.path, 'template', 'lib', 'extra.txt'))
              .readAsStringSync(),
          'extra for {{ package_name }}\n',
        );

        final castResult = await runFoundry(
          [
            'cast',
            moldDir.path,
            '--output=out',
            '--vars=package_name=acme_app',
            '--skip-hooks=prepare',
            '--skip-hooks=shape',
            '--skip-hooks=finish',
          ],
          workingDirectory: workDir.path,
        );
        expect(castResult.exitCode, 0, reason: castResult.stderr);
        expect(castResult.stdout, contains('Cast completed'));

        expectDirectoryTreesMatch(
          expected: expectedDirectory,
          actual: Directory(p.join(workDir.path, 'out')),
        );
      },
      tags: const ['e2e'],
      // Spawns the CLI for derive, sync, and cast; mold inspect/load also
      // runs pub get against the local foundry_core path dependency.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await File(targetPath).parent.create(recursive: true);
      await entity.copy(targetPath);
    }
  }
}
