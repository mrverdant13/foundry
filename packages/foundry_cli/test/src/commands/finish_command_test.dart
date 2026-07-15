import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/commands/finish_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cast_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_finish_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  CommandRunner<int> buildRunner({
    required Directory workingDirectory,
    CastStateReader? readState,
    FinishHookRunner? runFinishHook,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        FinishCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          readState: readState,
          runFinishHook: runFinishHook,
        ),
      );
  }

  Future<void> writeCastState(
    Directory cwd, {
    required String moldPath,
    required String outputPath,
    Map<String, Object?> vars = const {'project_name': 'Ada'},
  }) async {
    final foundryDir = Directory(p.join(cwd.path, '.foundry'))..createSync();
    await File(p.join(foundryDir.path, 'last_cast.json')).writeAsString(
      jsonEncode({
        'moldPath': moldPath,
        'outputPath': outputPath,
        'vars': vars,
        'timestamp': '2026-01-01T00:00:00.000Z',
      }),
    );
  }

  group('FinishCommand', () {
    test('fails with a clear error when no prior cast state exists', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Run `foundry cast` first')));
    });

    test(
      'fails with a clear error when --no-hooks is passed without cast state',
      () async {
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['finish', '--no-hooks']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('Run `foundry cast` first')));
      },
    );

    test(
      'fails with a user error when last_cast.json is not valid JSON',
      () async {
        final foundryDir = Directory(p.join(workDir.path, '.foundry'))
          ..createSync();
        await File(p.join(foundryDir.path, 'last_cast.json'))
            .writeAsString('not json');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('invalid or corrupted')));
      },
    );

    test(
      'fails with a user error when last_cast.json has an unexpected shape',
      () async {
        final foundryDir = Directory(p.join(workDir.path, '.foundry'))
          ..createSync();
        await File(p.join(foundryDir.path, 'last_cast.json')).writeAsString(
          jsonEncode({'moldPath': 'mold'}),
        );
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('invalid or corrupted')));
      },
    );

    test('fails with a usage error when given positional arguments', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['finish', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'fails with a clear error when the mold has no finish hook defined',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        Directory(p.join(workDir.path, 'out')).createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('No finish hook defined')));
        expect(errorMessages, contains(contains(MoldHooks.finishPath)));
      },
    );

    test(
      'runs the finish hook without re-rendering templates',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMoldWithFinishHook(
          directory: moldDir,
          name: 'demo_app',
        );
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        final artifact = File(p.join(outputDir.path, 'README.md'));
        await artifact.writeAsString('# stale template output\n');
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(infoMessages, contains('✓ Finish completed'));
        expect(await artifact.readAsString(), '# stale template output\n');
        expect(
          File(p.join(outputDir.path, 'finish_marker.txt')).readAsStringSync(),
          'done',
        );
      },
    );

    test('skips the finish hook when --no-hooks is passed', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMoldWithFinishHook(
        directory: moldDir,
        name: 'demo_app',
      );
      final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['finish', '--no-hooks']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('skipped (--no-hooks)')));
      expect(
        File(p.join(outputDir.path, 'finish_marker.txt')).existsSync(),
        isFalse,
      );
    });

    test('fails with a user error when a finish hook throws', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMoldWithFinishHook(
        directory: moldDir,
        name: 'demo_app',
      );
      final hooksDir = Directory(p.join(moldDir.path, 'hooks'));
      await File(p.join(hooksDir.path, 'finish.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  throw const FoundryHookException('finish always fails');
}
''');
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('MoldHookException(finish,')),
      );
    });

    test('fails with a user error when the mold cannot be loaded', () async {
      await writeCastState(
        workDir,
        moldPath: 'does_not_exist',
        outputPath: 'out',
      );
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test(
      'fails with a user error when the stored output directory is missing',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMoldWithFinishHook(
          directory: moldDir,
          name: 'demo_app',
        );
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Output directory "out" does not exist')),
        );
      },
    );
  });
}
