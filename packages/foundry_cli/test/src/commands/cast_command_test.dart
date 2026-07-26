import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
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
    CastPreparer? prepareCast,
    CastCompleter? completeCastRun,
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
          gatherVariables: gatherVariables,
          prepareCast: prepareCast,
          completeCastRun: completeCastRun,
          readVarsFileContents: readVarsFileContents,
          launchBatchSession: launchBatchSession,
        ),
      );
  }

  Map<String, Object?> readCastState(Directory cwd) {
    final file = File(p.join(cwd.path, '.foundry', 'last_cast.json'));
    return json.decode(file.readAsStringSync()) as Map<String, Object?>;
  }

  group('CastCommand', () {
    test('defaults workingDirectory to Directory.current', () {
      final command = CastCommand(logger: Logger());
      expect(command.workingDirectory.path, Directory.current.path);
    });

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
            seedValues = const {},
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
            seedValues = const {},
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
            seedValues = const {},
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
            seedValues = const {},
          }) async =>
              null,
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(infoMessages, contains(contains('cancelled')));
        // Prepare creates --output before gather; cancel removes it when empty.
        expect(Directory(p.join(workDir.path, 'out')).existsSync(), isFalse);
      },
    );

    test(
      'warns when cancel leaves a non-empty --output directory in place',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMoldWithPrepareArtifact(
          directory: moldDir,
          name: 'demo_app',
        );
        final infoMessages = <String>[];
        final warnMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          onWarn: warnMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async =>
              null,
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

    test('runs prepare before gather and passes seedValues', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      Map<String, Object?>? seenSeed;
      final runner = buildRunner(
        workingDirectory: workDir,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          seenSeed = Map<String, Object?>.of(seedValues);
          return {'project_name': 'Ada'};
        },
      );

      final exitCode = await runner.run(['cast', 'mold', '--output=out']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(seenSeed, isNotNull);
      expect(seenSeed!['from_prepare'], 'yes');
    });

    test('does not seed gather from prepare when --no-hooks is set', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeCastableMold(
        directory: moldDir,
        name: 'demo_app',
        withHooks: true,
      );
      Map<String, Object?>? seenSeed;
      final runner = buildRunner(
        workingDirectory: workDir,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          seenSeed = Map<String, Object?>.of(seedValues);
          return {'project_name': 'Ada'};
        },
      );

      final exitCode = await runner.run(
        ['cast', 'mold', '--output=out', '--no-hooks'],
      );

      expect(exitCode, FoundryExitCode.success.code);
      expect(seenSeed, isNotNull);
      expect(seenSeed!.containsKey('from_prepare'), isFalse);
    });

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
          seedValues = const {},
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
          seedValues = const {},
        }) async =>
            {'project_name': 'Ada'},
      );

      final exitCode = await runner.run(['cast', 'mold', '--output=out']);

      expect(exitCode, FoundryExitCode.success.code);
      final state = readCastState(workDir);
      expect((state['vars']! as Map)['from_prepare'], 'yes');
    });

    test(
      'fails with a user error when cast-time variable validation fails',
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
            seedValues = const {},
          }) async =>
              {'project_name': 'Ada'},
          completeCastRun: ({
            required mold,
            required context,
            force = false,
            noHooks = false,
          }) async {
            throw const CastVariablesInvalidException(
              FoundryVariableGroupValidation(
                fieldErrors: {
                  'project_name': ['project_name is invalid at cast time'],
                },
                groupErrors: ['group validation failed at cast time'],
              ),
            );
          },
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
          errorMessages,
          contains(contains('group validation failed at cast time')),
        );
      },
    );

    test('fails with a user error when a mold hook throws', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeHookFailingMold(directory: moldDir, name: 'demo_app');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async =>
            {'project_name': 'Ada'},
      );

      final exitCode = await runner.run(['cast', 'mold', '--output=out']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('MoldHookException(prepare,')),
      );
      // Prepare creates --output before the hook runs; failure removes it
      // when empty.
      expect(Directory(p.join(workDir.path, 'out')).existsSync(), isFalse);
    });

    test(
      'fails with a user error when a finish hook throws during complete',
      () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeFinishHookFailingMold(directory: moldDir, name: 'demo_app');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async =>
              {'project_name': 'Ada'},
        );

        final exitCode = await runner.run(['cast', 'mold', '--output=out']);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(
          errorMessages,
          contains(contains('MoldHookException(finish,')),
        );
      },
    );

    test('fails with a user error when template rendering fails', () async {
      final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
      await writeBrokenTemplateMold(directory: moldDir, name: 'demo_app');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async =>
            {'project_name': 'Ada'},
      );

      final exitCode = await runner.run(['cast', 'mold', '--output=out']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('Failed to render contents of template file')),
      );
    });

    group('batch --vars / --vars-file', () {
      test('routes --vars through the batch session launcher', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        var gatherCalls = 0;
        var launchCalls = 0;
        final infoMessages = <String>[];
        final captured = <String, Object?>{};
        final runner = buildRunner(
          workingDirectory: workDir,
          onInfo: infoMessages.add,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async {
            gatherCalls++;
            return {'project_name': 'should_not_be_used'};
          },
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            varsFlag,
            force = false,
            noHooks = false,
          }) async {
            launchCalls++;
            captured['moldPath'] = moldPath;
            captured['outputPath'] = outputPath;
            captured['varsFlag'] = varsFlag;
            captured['varsFileValues'] = varsFileValues;
            captured['force'] = force;
            captured['noHooks'] = noHooks;
            Directory(outputPath).createSync(recursive: true);
            await File(
              p.join(outputPath, 'README.md'),
            ).writeAsString('# Ada\n');
            return MoldCastSessionLaunchSuccess(
              artifactCount: 1,
              vars: const {'project_name': 'Ada'},
              writtenFilePaths: [p.join(outputPath, 'README.md')],
              outputDirectory: outputPath,
              exitCode: FoundryExitCode.success.code,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(gatherCalls, 0);
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
        var gatherCalls = 0;
        Map<String, Object?>? launchedVarsFile;
        final runner = buildRunner(
          workingDirectory: workDir,
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async {
            gatherCalls++;
            return null;
          },
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            varsFlag,
            force = false,
            noHooks = false,
          }) async {
            launchedVarsFile = varsFileValues;
            Directory(outputPath).createSync(recursive: true);
            return const MoldCastSessionLaunchSuccess(
              artifactCount: 1,
              vars: {'project_name': 'Ada'},
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

        expect(exitCode, FoundryExitCode.success.code);
        expect(gatherCalls, 0);
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
            launchBatchSession: ({
              required moldPath,
              required outputPath,
              varsFileValues,
              varsFlag,
              force = false,
              noHooks = false,
            }) async {
              captured['varsFileValues'] = varsFileValues;
              captured['varsFlag'] = varsFlag;
              captured['force'] = force;
              captured['noHooks'] = noHooks;
              return const MoldCastSessionLaunchSuccess(
                artifactCount: 0,
                vars: {'project_name': 'FromFlag'},
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

      test('surfaces session load failures with their exit code', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            varsFlag,
            force = false,
            noHooks = false,
          }) async {
            return const MoldCastSessionLaunchFailure(
              kind: 'load',
              message: 'Missing required file "pubspec.yaml".',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('pubspec.yaml')));
        expect(
          File(p.join(workDir.path, '.foundry', 'last_cast.json')).existsSync(),
          isFalse,
        );
      });

      test('surfaces session parse failures with their exit code', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            varsFlag,
            force = false,
            noHooks = false,
          }) async {
            return const MoldCastSessionLaunchFailure(
              kind: 'parse',
              message: 'Unknown variable "unknown".',
              exitCode: 1,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada,unknown=x',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('unknown')));
        expect(
          File(p.join(workDir.path, '.foundry', 'last_cast.json')).existsSync(),
          isFalse,
        );
      });

      test('surfaces session internal failures with exit code 2', () async {
        Directory(p.join(workDir.path, 'mold')).createSync();
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          launchBatchSession: ({
            required moldPath,
            required outputPath,
            varsFileValues,
            varsFlag,
            force = false,
            noHooks = false,
          }) async {
            return const MoldCastSessionLaunchFailure(
              kind: 'internal',
              message: 'Session process did not produce a result payload.',
              exitCode: 2,
            );
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada',
        ]);

        expect(exitCode, FoundryExitCode.internalError.code);
        expect(
          errorMessages,
          contains(contains('did not produce a result payload')),
        );
      });

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
            varsFlag,
            force = false,
            noHooks = false,
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
            varsFlag,
            force = false,
            noHooks = false,
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
            varsFlag,
            force = false,
            noHooks = false,
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
              varsFlag,
              force = false,
              noHooks = false,
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
        'uses the interactive gatherer when batch flags are omitted',
        () async {
          final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
          await writeCastableMold(directory: moldDir, name: 'demo_app');
          var gatherCalls = 0;
          var launchCalls = 0;
          final runner = buildRunner(
            workingDirectory: workDir,
            gatherVariables: ({
              required variableGroup,
              required moldName,
              required moldDescription,
              seedValues = const {},
            }) async {
              gatherCalls++;
              return {'project_name': 'Ada'};
            },
            launchBatchSession: ({
              required moldPath,
              required outputPath,
              varsFileValues,
              varsFlag,
              force = false,
              noHooks = false,
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

          expect(exitCode, FoundryExitCode.success.code);
          expect(gatherCalls, 1);
          expect(launchCalls, 0);
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
