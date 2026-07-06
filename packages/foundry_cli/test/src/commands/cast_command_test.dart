import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cast_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_cast_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  CommandRunner<int> buildRunner({
    required Directory workingDirectory,
    CastVariableGatherer? gatherVariables,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        CastCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          gatherVariables: gatherVariables,
        ),
      );
  }

  Map<String, Object?> readCastState(Directory cwd) {
    final file = File(p.join(cwd.path, '.foundry', 'last_cast.json'));
    return json.decode(file.readAsStringSync()) as Map<String, Object?>;
  }

  group('CastCommand', () {
    test(
      'casts a fixture mold, writes artifacts, and persists cast state',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
          }) async =>
              {'project_name': 'Ada'},
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(infoMessages, contains('✓ Cast completed'));
        expect(infoMessages, contains(contains('1 artifacts generated')));
        final artifact = File(p.join(workDir.path, 'out', 'README.md'));
        expect(artifact.existsSync(), isTrue);
        expect(await artifact.readAsString(), '# Ada\n');

        final state = readCastState(workDir);
        expect(state['moldPath'], 'mold');
        expect(state['outputPath'], 'out');
        expect((state['vars']! as Map)['project_name'], 'Ada');
      },
    );

    test('fails with a usage error when --output is missing', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(directory: moldDir, name: 'demo_app');
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['cast', 'mold']),
        throwsA(isA<UsageException>()),
      );
    });

    test('fails with a usage error when <mold-path> is missing', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['cast', '--output=out']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'fails with a usage error when given more than one <mold-path>',
      () async {
        final runner = buildRunner(workingDirectory: workDir);

        await expectLater(
          runner.run(['cast', 'a', 'b', '--output=out']),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test('fails with a user error when the mold cannot be loaded', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(
        ['cast', 'does_not_exist', '--output=out'],
      );

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test(
      'fails with a user error when --output exists and is non-empty '
      'without --force',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(
          p.join(outputDir.path, 'existing.txt'),
        ).writeAsStringSync('hi');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('--force')));
      },
    );

    test(
      'allows casting into a non-empty --output directory with --force',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(
          p.join(outputDir.path, 'existing.txt'),
        ).writeAsStringSync('hi');
        final runner = buildRunner(
          workingDirectory: workDir,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
          }) async =>
              {'project_name': 'Ada'},
        );

        final exitCode = await runner.run(
          ['cast', 'mold', '--output=out', '--force'],
        );

        expect(exitCode, FoundryExitCode.success.code);
        expect(
          File(p.join(outputDir.path, 'existing.txt')).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'fails with a user error naming the variable when a gathered value '
      "doesn't match its declared type",
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
          }) async =>
              {'project_name': 42},
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('project_name')));
      },
    );

    test(
      'exits with a user error when the user cancels variable gathering',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
          }) async =>
              null,
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(infoMessages, contains(contains('cancelled')));
      },
    );

    test('skips hooks when --no-hooks is passed', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      final runner = buildRunner(
        workingDirectory: workDir,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
        }) async =>
            {'project_name': 'Ada'},
      );

      final exitCode = await runner.run(
        ['cast', 'mold', '--output=out', '--no-hooks'],
      );

      expect(exitCode, FoundryExitCode.success.code);
      final state = readCastState(workDir);
      expect((state['vars']! as Map).containsKey('from_prepare'), isFalse);
    });

    test('runs hooks by default', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      final runner = buildRunner(
        workingDirectory: workDir,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
        }) async =>
            {'project_name': 'Ada'},
      );

      final exitCode = await runner.run(['cast', 'mold', '--output=out']);

      expect(exitCode, FoundryExitCode.success.code);
      final state = readCastState(workDir);
      expect((state['vars']! as Map)['from_prepare'], 'yes');
    });
  });
}
