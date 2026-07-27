import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    VarsFileContentsReader? readVarsFileContents,
    BatchMoldCastSessionLauncher? launchBatchSession,
    void Function(String message)? onInfo,
    void Function(String message)? onWarn,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        CastCommand(
          logger: Logger(onInfo: onInfo, onWarn: onWarn, onError: onError),
          workingDirectory: workingDirectory,
          readVarsFileContents: readVarsFileContents,
          launchBatchSession: launchBatchSession,
        ),
      );
  }

  Map<String, Object?> readCastState(Directory cwd) {
    final file = File(p.join(cwd.path, '.foundry', 'last_cast.json'));
    return json.decode(file.readAsStringSync()) as Map<String, Object?>;
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

  group('CastCommand', () {
    test('defaults workingDirectory to Directory.current', () {
      final command = CastCommand(logger: Logger());
      expect(command.workingDirectory.path, Directory.current.path);
    });

    test(
      'casts via the session launcher and persists cast state',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          launchBatchSession: successfulLauncher(),
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
        launchBatchSession: ({
          required moldPath,
          required outputPath,
          varsFileValues,
          seededValues,
          varsFlag,
          force = false,
          noHooks = false,
          finishOnly = false,
        }) async =>
            const MoldCastSessionLaunchFailure(
          kind: 'load',
          message: 'Mold directory does not exist: does_not_exist',
          exitCode: 1,
        ),
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
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(
          p.join(outputDir.path, 'existing.txt'),
        ).writeAsStringSync('hi');
        final errorMessages = <String>[];
        var launchCalls = 0;
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
            launchCalls++;
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 0,
              vars: {},
              writtenFilePaths: [],
              outputDirectory: 'out',
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(launchCalls, 0);
        expect(errorMessages, contains(contains('--force')));
      },
    );

    test(
      'allows casting into a non-empty --output directory with --force',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final outputDir = Directory(p.join(workDir.path, 'out'))..createSync();
        File(
          p.join(outputDir.path, 'existing.txt'),
        ).writeAsStringSync('hi');
        final runner = buildRunner(
          workingDirectory: workDir,
          launchBatchSession: successfulLauncher(),
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
      'exits with a user error when interactive gather is cancelled',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final infoMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
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
            // Session prepare creates --output before gather cancel.
            Directory(outputPath).createSync(recursive: true);
            return const MoldCastSessionLaunchFailure(
              kind: 'cancel',
              message: 'Cast cancelled.',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(infoMessages, contains(contains('cancelled')));
        expect(Directory(p.join(workDir.path, 'out')).existsSync(), isFalse);
      },
    );

    test(
      'warns when cancel leaves a non-empty --output directory in place',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final infoMessages = <String>[];
        final warnMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          onWarn: warnMessages.add,
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
            Directory(outputPath).createSync(recursive: true);
            await File(
              p.join(outputPath, 'prepare_artifact.txt'),
            ).writeAsString('prepared');
            return const MoldCastSessionLaunchFailure(
              kind: 'cancel',
              message: 'Cast cancelled.',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(infoMessages, contains(contains('cancelled')));
        expect(
          warnMessages,
          contains(contains('is not empty; left in place after aborted cast')),
        );
        final leftover = File(
          p.join(workDir.path, 'out', 'prepare_artifact.txt'),
        );
        expect(leftover.existsSync(), isTrue);
        expect(await leftover.readAsString(), 'prepared');
      },
    );

    test('forwards --no-hooks to the session launcher', () async {
      Directory(p.join(workDir.path, 'mold')).createSync();
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

      final exitCode = await runner.run(
        ['cast', 'mold', '--output=out', '--no-hooks'],
      );

      expect(exitCode, FoundryExitCode.success.code);
      expect(seenNoHooks, isTrue);
    });

    test(
      'removes empty --output when a prepare hook failure is reported',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
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
            Directory(outputPath).createSync(recursive: true);
            return const MoldCastSessionLaunchFailure(
              kind: 'hook',
              message: 'MoldHookException(prepare, hooks/prepare.dart): boom',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('MoldHookException(prepare')));
        expect(Directory(p.join(workDir.path, 'out')).existsSync(), isFalse);
      },
    );

    test(
      'removes empty --output when a gather failure is reported',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
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
            // Session creates --output before gather fails (e.g. bad
            // FOUNDRY_E2E_VARS).
            Directory(outputPath).createSync(recursive: true);
            return const MoldCastSessionLaunchFailure(
              kind: 'gather',
              message: 'FOUNDRY_E2E_VARS must be valid JSON: FormatException',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('FOUNDRY_E2E_VARS')));
        expect(Directory(p.join(workDir.path, 'out')).existsSync(), isFalse);
      },
    );

    test(
      'surfaces validation failures from the session without writing state',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
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
          }) async =>
              const MoldCastSessionLaunchFailure(
            kind: 'validation',
            message: 'Cast variables are invalid:\n'
                '  project_name: project_name is invalid at cast time\n'
                '  group validation failed at cast time',
            exitCode: 1,
          ),
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Cast variables are invalid:')),
        );
        expect(
          errorMessages,
          contains(
            contains('project_name: project_name is invalid at cast time'),
          ),
        );
        expect(
          File(
            p.join(workDir.path, '.foundry', 'last_cast.json'),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'surfaces render failures from the session without writing state',
      () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
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
          }) async =>
              const MoldCastSessionLaunchFailure(
            kind: 'render',
            message: 'Failed to render contents of template file README.md',
            exitCode: 1,
          ),
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('Failed to render contents of template file')),
        );
      },
    );

    group('batch --vars / --vars-file', () {
      test('routes --vars through the batch session launcher', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        var launchCalls = 0;
        final infoMessages = <String>[];
        final captured = <String, Object?>{};
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
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
              launchCalls++;
              captured['moldPath'] = moldPath;
              captured['outputPath'] = outputPath;
              captured['varsFlag'] = varsFlag;
              captured['varsFileValues'] = varsFileValues;
              captured['force'] = force;
              captured['noHooks'] = noHooks;
            },
          ),
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(launchCalls, 1);
        expect(captured['varsFlag'], 'project_name=Ada');
        expect(captured['varsFileValues'], isNull);
        expect(captured['force'], isFalse);
        expect(captured['noHooks'], isFalse);
        expect(
          captured['moldPath'],
          p.normalize(p.join(workDir.path, 'mold')),
        );
        expect(
          captured['outputPath'],
          p.normalize(p.join(workDir.path, 'out')),
        );
        expect(infoMessages, contains('✓ Cast completed'));
        expect(
          infoMessages,
          contains(
            contains('1 artifacts generated at'),
          ),
        );
        final state = readCastState(workDir);
        expect(state['moldPath'], 'mold');
        expect(state['outputPath'], 'out');
        expect(state['vars'], {'project_name': 'Ada'});
        expect(
          await File(p.join(workDir.path, 'out', 'README.md')).readAsString(),
          '# Ada\n',
        );
      });

      test('routes --vars-file through the batch session launcher', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync(
          json.encode({'project_name': 'Ada'}),
        );
        Map<String, Object?>? launchedVarsFile;
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
              launchedVarsFile = varsFileValues;
            },
          ),
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(launchedVarsFile, {'project_name': 'Ada'});
        expect(readCastState(workDir)['vars'], {'project_name': 'Ada'});
      });

      test(
        'forwards --vars, --force, and --no-hooks to the launcher',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          File(p.join(workDir.path, 'vars.json')).writeAsStringSync(
            json.encode({'project_name': 'FromFile'}),
          );
          final captured = <String, Object?>{};
          final runner = buildRunner(
            workingDirectory: workDir,
            launchBatchSession: successfulLauncher(
              vars: const {'project_name': 'FromFlag'},
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
                captured['varsFileValues'] = varsFileValues;
                captured['varsFlag'] = varsFlag;
                captured['force'] = force;
                captured['noHooks'] = noHooks;
              },
            ),
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars-file=vars.json',
            '--vars=project_name=FromFlag',
            '--force',
            '--no-hooks',
          ]);

          expect(exitCode, FoundryExitCode.success.code);
          expect(captured['varsFileValues'], {'project_name': 'FromFile'});
          expect(captured['varsFlag'], 'project_name=FromFlag');
          expect(captured['force'], isTrue);
          expect(captured['noHooks'], isTrue);
        },
      );

      test(
        'forwards session load failure exit codes to the process',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          const failure = MoldCastSessionLaunchFailure(
            kind: 'load',
            message: 'Missing required file "pubspec.yaml".',
            exitCode: 1,
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
              noHooks = false,
              finishOnly = false,
            }) async =>
                failure,
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars=project_name=Ada',
          ]);

          expect(exitCode, failure.exitCode);
          expect(errorMessages, contains(contains('pubspec.yaml')));
          expect(
            File(
              p.join(workDir.path, '.foundry', 'last_cast.json'),
            ).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'forwards session parse failure exit codes to the process',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          const failure = MoldCastSessionLaunchFailure(
            kind: 'parse',
            message: 'Unknown variable "unknown".',
            exitCode: 1,
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
              noHooks = false,
              finishOnly = false,
            }) async =>
                failure,
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars=project_name=Ada,unknown=x',
          ]);

          expect(exitCode, failure.exitCode);
          expect(errorMessages, contains(contains('unknown')));
          expect(
            File(
              p.join(workDir.path, '.foundry', 'last_cast.json'),
            ).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'forwards session internal failure exit codes to the process',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          const failure = MoldCastSessionLaunchFailure(
            kind: 'internal',
            message: 'Session process did not produce a result payload.',
            exitCode: 2,
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
              noHooks = false,
              finishOnly = false,
            }) async =>
                failure,
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars=project_name=Ada',
          ]);

          expect(exitCode, failure.exitCode);
          expect(
            errorMessages,
            contains(contains('did not produce a result payload')),
          );
        },
      );

      test('fails with exit 1 when --vars-file is missing', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        var launchCalls = 0;
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
            launchCalls++;
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 0,
              vars: {},
              writtenFilePaths: [],
              outputDirectory: 'out',
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=missing.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(launchCalls, 0);
        expect(errorMessages, contains(contains('does not exist')));
      });

      test('fails with exit 1 when --vars-file cannot be read', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync('{}');
        var launchCalls = 0;
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          readVarsFileContents: (file) async {
            throw FileSystemException('Permission denied', file.path);
          },
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
            launchCalls++;
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 0,
              vars: {},
              writtenFilePaths: [],
              outputDirectory: 'out',
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(launchCalls, 0);
        expect(errorMessages, contains(contains('Failed to read vars file')));
      });

      test('fails with exit 1 when --vars-file is not valid JSON', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync('{not-json');
        var launchCalls = 0;
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
            launchCalls++;
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 0,
              vars: {},
              writtenFilePaths: [],
              outputDirectory: 'out',
              exitCode: 0,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(launchCalls, 0);
        expect(errorMessages, contains(contains('not valid JSON')));
      });

      test(
        'fails with exit 1 when --vars-file is not a JSON object',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          File(p.join(workDir.path, 'vars.json')).writeAsStringSync('[1, 2]');
          var launchCalls = 0;
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
              launchCalls++;
              return const MoldCastSessionLaunchSuccess(
                artifactCount: 0,
                vars: {},
                writtenFilePaths: [],
                outputDirectory: 'out',
                exitCode: 0,
              );
            },
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars-file=vars.json',
          ]);

          expect(exitCode, FoundryExitCode.userError.code);
          expect(launchCalls, 0);
          expect(
            errorMessages,
            contains(contains('must contain a JSON object')),
          );
        },
      );

      test(
        'routes interactive cast through the session launcher when batch '
        'flags are omitted',
        () async {
          Directory(p.join(workDir.path, 'mold')).createSync();
          var launchCalls = 0;
          String? launchedVarsFlag;
          Map<String, Object?>? launchedVarsFile;
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
                launchCalls++;
                launchedVarsFlag = varsFlag;
                launchedVarsFile = varsFileValues;
              },
            ),
          );

          final exitCode = await runner.run(['cast', 'mold', '--output=out']);

          expect(exitCode, FoundryExitCode.success.code);
          expect(launchCalls, 1);
          expect(launchedVarsFlag, isNull);
          expect(launchedVarsFile, isNull);
        },
      );

      test('help text documents --vars and --vars-file', () async {
        final runner = buildRunner(workingDirectory: workDir);
        final cast = runner.commands['cast']!;
        final help = cast.argParser.usage;

        expect(cast.description, isNotEmpty);
        expect(help, contains('--vars'));
        expect(help, contains('--vars-file'));
      });
    });
  });
}
