import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry cast, recast, and finish', () {
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
      'casts a fixture mold, recasts from persisted state, then finishes',
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

        final finishMarker = File(
          p.join(outputDirectory.path, 'cast_complete.txt'),
        );
        await finishMarker.delete();
        final readmeBeforeFinish =
            await File(p.join(outputDirectory.path, 'README.md'))
                .readAsString();

        final finishResult = await runFoundry(
          ['finish'],
          workingDirectory: workDir.path,
        );

        expect(finishResult.exitCode, 0, reason: finishResult.stderr);
        expect(finishResult.stdout, contains('Finish completed'));
        expect(await finishMarker.readAsString(), 'finished\n');
        expect(
          await File(p.join(outputDirectory.path, 'README.md')).readAsString(),
          readmeBeforeFinish,
        );
      },
      tags: const ['e2e'],
      // Cast, recast, and finish each spawn the CLI and a mold session helper
      // (pub get + bridge) — well over the default 30s on cold CI runners.
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'rejects --skip-hooks finish when hooks/policy.dart requires finish',
      () async {
        final castResult = await runFoundry(
          [
            'cast',
            moldPath,
            '--output=out',
            '--vars=project_name=my project',
            '--skip-hooks=finish',
          ],
          workingDirectory: workDir.path,
        );

        expect(castResult.exitCode, isNot(0));
        expect(
          '${castResult.stdout}${castResult.stderr}',
          contains('Cannot skip required hook phase(s): finish'),
        );
      },
      tags: const ['e2e'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'finish ignores prepare-only policy requirements',
      () async {
        final moldCopy = Directory(p.join(workDir.path, 'mold'))..createSync();
        await _copyMoldWithPolicy(
          sourceMoldPath: moldPath,
          destination: moldCopy,
          policySource: "import 'package:foundry_core/foundry_core.dart';\n\n"
              'Future<Set<MoldHookPhase>> get requiredHooks async => {\n'
              '  MoldHookPhase.prepare,\n'
              '};\n',
        );
        // Remove prepare so a full-pipeline validation would fail.
        await File(p.join(moldCopy.path, 'hooks', 'prepare.dart')).delete();

        final castResult = await runFoundry(
          [
            'cast',
            moldCopy.path,
            '--output=out',
            '--vars=project_name=my project',
            '--skip-hooks=prepare',
          ],
          workingDirectory: workDir.path,
        );
        expect(castResult.exitCode, isNot(0), reason: castResult.stderr);

        // Seed cast state + output as if cast had completed earlier.
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        await File(p.join(outputDir.path, 'README.md')).writeAsString('# ok\n');
        await Directory(p.join(workDir.path, '.foundry')).create();
        await File(p.join(workDir.path, '.foundry', 'last_cast.json'))
            .writeAsString(
          jsonEncode({
            'moldPath': moldCopy.path,
            'outputPath': 'out',
            'vars': {'project_name': 'my project'},
            'timestamp': '2026-01-01T00:00:00.000Z',
          }),
        );

        final finishResult = await runFoundry(
          ['finish'],
          workingDirectory: workDir.path,
        );

        expect(finishResult.exitCode, 0, reason: finishResult.stderr);
        expect(finishResult.stdout, contains('Finish completed'));
        expect(
          await File(p.join(outputDir.path, 'cast_complete.txt'))
              .readAsString(),
          'finished\n',
        );
      },
      tags: const ['e2e'],
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'finish --skip-hooks finish no-ops when finish is not required',
      () async {
        final moldCopy = Directory(p.join(workDir.path, 'mold'))..createSync();
        await _copyMoldWithPolicy(
          sourceMoldPath: moldPath,
          destination: moldCopy,
          policySource: "import 'package:foundry_core/foundry_core.dart';\n\n"
              'Future<Set<MoldHookPhase>> get requiredHooks async => {};\n',
        );

        final castResult = await runFoundry(
          [
            'cast',
            moldCopy.path,
            '--output=out',
            '--vars=project_name=my project',
          ],
          workingDirectory: workDir.path,
        );
        expect(castResult.exitCode, 0, reason: castResult.stderr);

        final finishMarker = File(
          p.join(workDir.path, 'out', 'cast_complete.txt'),
        );
        await finishMarker.delete();

        final finishResult = await runFoundry(
          ['finish', '--skip-hooks=finish'],
          workingDirectory: workDir.path,
        );

        expect(finishResult.exitCode, 0, reason: finishResult.stderr);
        expect(
          finishResult.stdout,
          contains('Finish skipped (--skip-hooks finish).'),
        );
        expect(finishMarker.existsSync(), isFalse);
      },
      tags: const ['e2e'],
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Future<void> _copyMoldWithPolicy({
  required String sourceMoldPath,
  required Directory destination,
  required String policySource,
}) async {
  await _copyDirectory(Directory(sourceMoldPath), destination);
  final foundryCorePath = Directory(
    p.normalize(
      p.join(sourceMoldPath, '..', '..', '..', '..', '..', 'foundry_core'),
    ),
  ).absolute.path;
  await File(p.join(destination.path, 'pubspec.yaml')).writeAsString(
    'name: cast_pipeline_mold\n'
    'description: E2E mold copy\n'
    'version: 0.0.1\n'
    'publish_to: none\n'
    '\n'
    'environment:\n'
    '  sdk: ">=3.5.0 <4.0.0"\n'
    '\n'
    'dependencies:\n'
    '  foundry_core:\n'
    '    path: ${jsonEncode(foundryCorePath)}\n',
  );
  await File(p.join(destination.path, 'hooks', 'policy.dart'))
      .writeAsString(policySource);
  final pubGet = await Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get'],
    workingDirectory: destination.path,
  );
  if (pubGet.exitCode != 0) {
    throw StateError(
      'dart pub get failed for mold copy: ${pubGet.stdout}${pubGet.stderr}',
    );
  }
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative == '.dart_tool' ||
        relative.startsWith('.dart_tool${p.separator}')) {
      continue;
    }
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await File(targetPath).parent.create(recursive: true);
      await entity.copy(targetPath);
    }
  }
}
