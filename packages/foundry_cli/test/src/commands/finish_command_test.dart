import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/commands/finish_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    BatchMoldCastSessionLauncher? launchBatchSession,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        FinishCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          readState: readState,
          launchBatchSession: launchBatchSession,
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

  BatchMoldCastSessionLauncher successfulFinishLauncher({
    void Function({
      required String moldPath,
      required String outputPath,
      Map<String, Object?>? varsFileValues,
      Map<String, Object?>? seededValues,
      String? varsFlag,
      bool force,
      Set<MoldHookPhase> skipHooks,
      bool finishOnly,
    })? onLaunch,
  }) {
    return ({
      required moldPath,
      required outputPath,
      varsFileValues,
      seededValues,
      varsFlag,
      force = false,
      skipHooks = const {},
      finishOnly = false,
    }) async {
      onLaunch?.call(
        moldPath: moldPath,
        outputPath: outputPath,
        varsFileValues: varsFileValues,
        seededValues: seededValues,
        varsFlag: varsFlag,
        force: force,
        skipHooks: skipHooks,
        finishOnly: finishOnly,
      );
      await File(p.join(outputPath, 'finish_marker.txt')).writeAsString('done');
      return MoldCastSessionLaunchSuccess(
        artifactCount: 0,
        vars: varsFileValues ?? const {},
        writtenFilePaths: const [],
        outputDirectory: outputPath,
        exitCode: FoundryExitCode.success.code,
      );
    };
  }

  group('FinishCommand', () {
    test('defaults workingDirectory to Directory.current', () {
      final command = FinishCommand(logger: Logger());
      expect(command.workingDirectory.path, Directory.current.path);
    });

    test('fails with a clear error when no prior cast state exists', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchBatchSession: successfulFinishLauncher(),
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Run `foundry cast` first')));
    });

    test(
      'fails with a clear error when --skip-hooks is passed without cast state',
      () async {
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: successfulFinishLauncher(),
        );

        final exitCode = await runner.run([
          'finish',
          '--skip-hooks=prepare',
          '--skip-hooks=shape',
          '--skip-hooks=finish',
        ]);

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
          launchBatchSession: successfulFinishLauncher(),
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
          launchBatchSession: successfulFinishLauncher(),
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('invalid or corrupted')));
      },
    );

    test('fails with a usage error when given positional arguments', () async {
      final runner = buildRunner(
        workingDirectory: workDir,
        launchBatchSession: successfulFinishLauncher(),
      );

      await expectLater(
        runner.run(['finish', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'launches a finish-only session seeded from last_cast vars',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        final artifact = File(p.join(outputDir.path, 'README.md'));
        await artifact.writeAsString('# stale template output\n');
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');

        String? seenMoldPath;
        Map<String, Object?>? seenVars;
        var seenFinishOnly = false;
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          launchBatchSession: successfulFinishLauncher(
            onLaunch: ({
              required moldPath,
              required outputPath,
              varsFileValues,
              seededValues,
              varsFlag,
              force = false,
              skipHooks = const {},
              finishOnly = false,
            }) {
              seenMoldPath = moldPath;
              seenVars = varsFileValues;
              seenFinishOnly = finishOnly;
            },
          ),
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(infoMessages, contains('✓ Finish completed'));
        expect(seenMoldPath, p.join(workDir.path, 'mold'));
        expect(seenVars, {'project_name': 'Ada'});
        expect(seenFinishOnly, isTrue);
        expect(await artifact.readAsString(), '# stale template output\n');
        expect(
          File(p.join(outputDir.path, 'finish_marker.txt')).readAsStringSync(),
          'done',
        );
      },
    );

    test('forwards --skip-hooks finish to the session launcher', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
      final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      Set<MoldHookPhase>? seenSkipHooks;
      var seenFinishOnly = false;
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
        launchBatchSession: successfulFinishLauncher(
          onLaunch: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            seededValues,
            varsFlag,
            force = false,
            skipHooks = const {},
            finishOnly = false,
          }) {
            seenSkipHooks = skipHooks;
            seenFinishOnly = finishOnly;
          },
        ),
      );

      final exitCode = await runner.run(['finish', '--skip-hooks=finish']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains('✓ Finish completed'));
      expect(seenFinishOnly, isTrue);
      expect(seenSkipHooks, {MoldHookPhase.finish});
      expect(
        File(p.join(outputDir.path, 'finish_marker.txt')).existsSync(),
        isTrue,
      );
    });

    test('rejects an invalid --skip-hooks phase name', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final runner = buildRunner(
        workingDirectory: workDir,
        launchBatchSession: successfulFinishLauncher(),
      );

      await expectLater(
        runner.run(['finish', '--skip-hooks=nope']),
        throwsA(isA<UsageException>()),
      );
    });

    test('surfaces missing finish hook failures from the session', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchBatchSession: ({
          required moldPath,
          required outputPath,
          varsFileValues,
          seededValues,
          varsFlag,
          force = false,
          skipHooks = const {},
          finishOnly = false,
        }) async {
          return MoldCastSessionLaunchFailure(
            kind: 'hook',
            message: 'No finish hook defined for mold "demo_app" at '
                '${MoldHooks.finishPath}.',
            exitCode: 1,
          );
        },
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('No finish hook defined')));
      expect(errorMessages, contains(contains(MoldHooks.finishPath)));
    });

    test('fails with a user error when a finish hook throws', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchBatchSession: ({
          required moldPath,
          required outputPath,
          varsFileValues,
          seededValues,
          varsFlag,
          force = false,
          skipHooks = const {},
          finishOnly = false,
        }) async {
          return const MoldCastSessionLaunchFailure(
            kind: 'hook',
            message: 'MoldHookException(finish, /tmp/hooks/finish.dart): boom',
            exitCode: 1,
          );
        },
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('MoldHookException(finish,')),
      );
    });

    test('fails with a user error when the mold cannot be loaded', () async {
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(
        workDir,
        moldPath: 'does_not_exist',
        outputPath: 'out',
      );
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchBatchSession: ({
          required moldPath,
          required outputPath,
          varsFileValues,
          seededValues,
          varsFlag,
          force = false,
          skipHooks = const {},
          finishOnly = false,
        }) async {
          return MoldCastSessionLaunchFailure(
            kind: 'load',
            message: 'Mold directory does not exist: $moldPath',
            exitCode: FoundryExitCode.userError.code,
          );
        },
      );

      final exitCode = await runner.run(['finish']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test(
      'fails with a user error when the stored output directory is missing',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        var launched = false;
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            seededValues,
            varsFlag,
            force = false,
            skipHooks = const {},
            finishOnly = false,
          }) async {
            launched = true;
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 0,
              vars: {},
              writtenFilePaths: [],
              outputDirectory: '',
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Output directory "out" does not exist')),
        );
        expect(launched, isFalse);
      },
    );

    test(
      'fails when the session returns an unexpected describe result',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        Directory(p.join(workDir.path, 'out')).createSync();
        await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            seededValues,
            varsFlag,
            force = false,
            skipHooks = const {},
            finishOnly = false,
          }) async {
            return const MoldCastSessionDescribeSuccess(
              variables: [],
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run(['finish']);

        expect(exitCode, FoundryExitCode.internalError.code);
        expect(
          errorMessages,
          contains(contains('unexpected describe session result')),
        );
      },
    );
  });
}
