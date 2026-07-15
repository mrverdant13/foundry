import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/commands/recast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cast_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_recast_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  CommandRunner<int> buildRunner({
    required Directory workingDirectory,
    CastStateReader? readState,
    CastRunner? runCast,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        RecastCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          readState: readState,
          runCast: runCast,
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

  group('RecastCommand', () {
    test('fails with a clear error when no prior cast state exists', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['recast']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Run `foundry cast` first')));
    });

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

        final exitCode = await runner.run(['recast']);

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

        final exitCode = await runner.run(['recast']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('invalid or corrupted')));
      },
    );

    test('fails with a usage error when given positional arguments', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['recast', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'repeats the last cast with the same paths and stored variable values',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final artifact = File(p.join(outputDir.path, 'README.md'));
        await artifact.writeAsString('# corrupted\n');
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(infoMessages, contains('✓ Recast completed'));
        expect(await artifact.readAsString(), '# Ada\n');
      },
    );

    test(
      'fails with a user error when output exists and is non-empty without '
      '--force',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(p.join(outputDir.path, 'existing.txt')).writeAsStringSync('hi');
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run(['recast']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('--force')));
      },
    );

    test('skips hooks when --no-hooks is passed', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final runner = buildRunner(workingDirectory: workDir);

      final exitCode = await runner.run(['recast', '--force', '--no-hooks']);

      expect(exitCode, FoundryExitCode.success.code);
      final stateFile = File(
        p.join(workDir.path, '.foundry', 'last_cast.json'),
      );
      final state = json.decode(stateFile.readAsStringSync()) as Map;
      expect((state['vars'] as Map).containsKey('from_prepare'), isFalse);
    });

    test('updates cast state after a successful recast', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final runner = buildRunner(workingDirectory: workDir);

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.success.code);
      final stateFile = File(
        p.join(workDir.path, '.foundry', 'last_cast.json'),
      );
      final state = json.decode(stateFile.readAsStringSync()) as Map;
      expect((state['vars'] as Map)['from_prepare'], 'yes');
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

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test(
      'fails with a user error when cast-time variable validation fails',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        Directory(p.join(workDir.path, 'out')).createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          runCast: ({
            required mold,
            required outputPath,
            required values,
            force = false,
            noHooks = false,
          }) async {
            throw const CastVariablesInvalidException(
              FoundryVariableGroupValidation(
                fieldErrors: {
                  'project_name': ['project_name is invalid at recast time'],
                },
                groupErrors: ['group validation failed at recast time'],
              ),
            );
          },
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Cast variables are invalid:')),
        );
        expect(
          errorMessages,
          contains(
            contains('project_name: project_name is invalid at recast time'),
          ),
        );
        expect(
          errorMessages,
          contains(contains('group validation failed at recast time')),
        );
      },
    );

    test(
      'fails with a user error when cast variable input is invalid',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        Directory(p.join(workDir.path, 'out')).createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          runCast: ({
            required mold,
            required outputPath,
            required values,
            force = false,
            noHooks = false,
          }) async {
            throw const FoundryContextException('invalid recast variable');
          },
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Invalid cast variable input: invalid recast')),
        );
      },
    );

    test('fails with a user error when a mold hook throws', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeHookFailingMold(directory: moldDir, name: 'demo_app');
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('MoldHookException(prepare,')),
      );
    });

    test('fails with a user error when template rendering fails', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeBrokenTemplateMold(directory: moldDir, name: 'demo_app');
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('Failed to render contents of template file')),
      );
    });
  });
}
