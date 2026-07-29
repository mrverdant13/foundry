import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/commands/recast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    BatchMoldCastSessionLauncher? launchBatchSession,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        RecastCommand(
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

  BatchMoldCastSessionLauncher successfulLauncher({
    int artifactCount = 1,
    Map<String, Object?> vars = const {'project_name': 'Ada'},
    void Function({
      required String moldPath,
      required String outputPath,
      Map<String, Object?>? varsFileValues,
      Map<String, Object?>? seededValues,
      String? varsFlag,
      bool force,
      bool noHooks,
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
      noHooks = false,
      finishOnly = false,
    }) async {
      onLaunch?.call(
        moldPath: moldPath,
        outputPath: outputPath,
        varsFileValues: varsFileValues,
        seededValues: seededValues,
        varsFlag: varsFlag,
        force: force,
        noHooks: noHooks,
        finishOnly: finishOnly,
      );
      Directory(outputPath).createSync(recursive: true);
      final artifact = File(p.join(outputPath, 'README.md'));
      await artifact.writeAsString('# ${vars['project_name'] ?? 'Ada'}\n');
      return MoldCastSessionLaunchSuccess(
        artifactCount: artifactCount,
        vars: vars,
        writtenFilePaths: [artifact.path],
        outputDirectory: outputPath,
        exitCode: FoundryExitCode.success.code,
      );
    };
  }

  group('RecastCommand', () {
    test('defaults workingDirectory to Directory.current', () {
      final command = RecastCommand(logger: Logger());
      expect(command.workingDirectory.path, Directory.current.path);
    });

    test('fails with a clear error when no prior cast state exists', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchBatchSession: successfulLauncher(),
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
          launchBatchSession: successfulLauncher(),
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
          launchBatchSession: successfulLauncher(),
        );

        final exitCode = await runner.run(['recast']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('invalid or corrupted')));
      },
    );

    test('fails with a usage error when given positional arguments', () async {
      final runner = buildRunner(
        workingDirectory: workDir,
        launchBatchSession: successfulLauncher(),
      );

      await expectLater(
        runner.run(['recast', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'launches a seeded session from last_cast vars and updates state',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        await writeCastState(
          workDir,
          moldPath: 'mold',
          outputPath: 'out',
          vars: const {
            'project_name': 'Ada',
            'optional_note': null,
            'seed': 'from-prepare',
          },
        );
        await File(p.join(outputDir.path, 'README.md'))
            .writeAsString('# corrupted\n');

        String? seenMoldPath;
        Map<String, Object?>? seenSeededValues;
        Map<String, Object?>? seenVarsFileValues;
        var seenForce = false;
        var seenNoHooks = true;
        var seenFinishOnly = true;
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          launchBatchSession: successfulLauncher(
            vars: const {
              'project_name': 'Ada',
              'from_prepare': 'yes',
            },
            onLaunch: ({
              required moldPath,
              required outputPath,
              varsFileValues,
              seededValues,
              varsFlag,
              force = false,
              noHooks = false,
              finishOnly = false,
            }) {
              seenMoldPath = moldPath;
              seenSeededValues = seededValues;
              seenVarsFileValues = varsFileValues;
              seenForce = force;
              seenNoHooks = noHooks;
              seenFinishOnly = finishOnly;
            },
          ),
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(infoMessages, contains('✓ Recast completed'));
        expect(
          infoMessages,
          contains('✓ 1 artifacts generated at .${p.separator}out'),
        );
        expect(seenMoldPath, p.join(workDir.path, 'mold'));
        expect(seenSeededValues, {
          'project_name': 'Ada',
          'optional_note': null,
          'seed': 'from-prepare',
        });
        expect(seenVarsFileValues, isNull);
        expect(seenForce, isTrue);
        expect(seenNoHooks, isFalse);
        expect(seenFinishOnly, isFalse);

        final state = json.decode(
          File(p.join(workDir.path, '.foundry', 'last_cast.json'))
              .readAsStringSync(),
        ) as Map<String, Object?>;
        expect(state['moldPath'], 'mold');
        expect(state['outputPath'], 'out');
        expect((state['vars']! as Map)['from_prepare'], 'yes');
        expect(
          await File(p.join(outputDir.path, 'README.md')).readAsString(),
          '# Ada\n',
        );
      },
    );

    test(
      'prints an absolute success path when stored output is outside cwd',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outsideOut = Directory.systemTemp.createTempSync(
          'foundry_recast_out_',
        );
        addTearDown(() {
          if (outsideOut.existsSync()) {
            outsideOut.deleteSync(recursive: true);
          }
        });
        await writeCastState(
          workDir,
          moldPath: 'mold',
          outputPath: outsideOut.path,
        );
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          launchBatchSession: successfulLauncher(),
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.success.code);
        expect(
          infoMessages,
          contains(
            '✓ 1 artifacts generated at ${p.normalize(outsideOut.path)}',
          ),
        );
      },
    );

    test(
      'fails with a user error when output exists and is non-empty without '
      '--force',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(p.join(outputDir.path, 'existing.txt')).writeAsStringSync('hi');
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
            noHooks = false,
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

        final exitCode = await runner.run(['recast']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('--force')));
        expect(launched, isFalse);
      },
    );

    test('forwards --no-hooks to the session launcher', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
      Directory(p.join(workDir.path, 'out')).createSync();
      await writeCastState(workDir, moldPath: 'mold', outputPath: 'out');
      var seenNoHooks = false;
      final runner = buildRunner(
        workingDirectory: workDir,
        launchBatchSession: successfulLauncher(
          onLaunch: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            seededValues,
            varsFlag,
            force = false,
            noHooks = false,
            finishOnly = false,
          }) {
            seenNoHooks = noHooks;
          },
        ),
      );

      final exitCode = await runner.run(['recast', '--force', '--no-hooks']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(seenNoHooks, isTrue);
    });

    test('surfaces session launch failures as user errors', () async {
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
          noHooks = false,
          finishOnly = false,
        }) async {
          return const MoldCastSessionLaunchFailure(
            kind: 'validation',
            message: 'Cast variables are invalid:\n  project_name: bad',
            exitCode: 1,
          );
        },
      );

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('Cast variables are invalid:')),
      );
      expect(errorMessages, contains(contains('project_name: bad')));
    });

    test('surfaces hook failures from the session launcher', () async {
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
          noHooks = false,
          finishOnly = false,
        }) async {
          return const MoldCastSessionLaunchFailure(
            kind: 'hook',
            message:
                'MoldHookException(prepare, /tmp/hooks/prepare.dart): boom',
            exitCode: 1,
          );
        },
      );

      final exitCode = await runner.run(['recast', '--force']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('MoldHookException(prepare,')),
      );
    });

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
            noHooks = false,
            finishOnly = false,
          }) async {
            return const MoldCastSessionDescribeSuccess(
              variables: [],
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run(['recast', '--force']);

        expect(exitCode, FoundryExitCode.internalError.code);
        expect(
          errorMessages,
          contains(contains('unexpected describe session result')),
        );
      },
    );
  });
}
