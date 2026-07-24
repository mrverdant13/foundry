import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
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
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        CastCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          gatherVariables: gatherVariables,
          prepareCast: prepareCast,
          completeCastRun: completeCastRun,
          readVarsFileContents: readVarsFileContents,
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
      test('casts successfully with --vars and skips the TUI', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        var gatherCalls = 0;
        final infoMessages = <String>[];
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
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(gatherCalls, 0);
        expect(infoMessages, contains('✓ Cast completed'));
        final artifact = File(p.join(workDir.path, 'out', 'README.md'));
        expect(artifact.existsSync(), isTrue);
        expect(await artifact.readAsString(), '# Ada\n');
      });

      test('casts successfully with --vars-file and skips the TUI', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync(
          json.encode({'project_name': 'Ada'}),
        );
        var gatherCalls = 0;
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
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(gatherCalls, 0);
        expect(
          await File(p.join(workDir.path, 'out', 'README.md')).readAsString(),
          '# Ada\n',
        );
      });

      test('--vars overrides colliding keys from --vars-file', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync(
          json.encode({'project_name': 'FromFile'}),
        );
        final runner = buildRunner(workingDirectory: workDir);

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
          '--vars=project_name=FromFlag',
        ]);

        expect(exitCode, FoundryExitCode.success.code);
        expect(
          await File(p.join(workDir.path, 'out', 'README.md')).readAsString(),
          '# FromFlag\n',
        );
      });

      test(
        'fails with exit 1 when batch input fails type parsing',
        () async {
          final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
          await writeNumericCastableMold(
            directory: moldDir,
            name: 'demo_app',
          );
          final errorMessages = <String>[];
          final runner = buildRunner(
            workingDirectory: workDir,
            onError: errorMessages.add,
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars=project_name=Ada,port=not-an-int',
          ]);

          expect(exitCode, FoundryExitCode.userError.code);
          expect(errorMessages, contains(contains('port')));
          expect(
            File(p.join(workDir.path, 'out', 'README.md')).existsSync(),
            isFalse,
          );
        },
      );

      test('fails with exit 1 for an unknown batch key', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars=project_name=Ada,unknown=x',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('unknown')));
      });

      test('fails with exit 1 when --vars-file is missing', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=missing.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('does not exist')));
      });

      test('fails with exit 1 when --vars-file cannot be read', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync('{}');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
          readVarsFileContents: (file) async {
            throw FileSystemException('Permission denied', file.path);
          },
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('Failed to read vars file')));
      });

      test('fails with exit 1 when --vars-file is not valid JSON', () async {
        final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
        await writeCastableMold(directory: moldDir, name: 'demo_app');
        File(p.join(workDir.path, 'vars.json')).writeAsStringSync('{not-json');
        final errorMessages = <String>[];
        final runner = buildRunner(
          workingDirectory: workDir,
          onError: errorMessages.add,
        );

        final exitCode = await runner.run([
          'cast',
          'mold',
          '--output=out',
          '--vars-file=vars.json',
        ]);

        expect(exitCode, FoundryExitCode.userError.code);
        expect(errorMessages, contains(contains('not valid JSON')));
      });

      test(
        'fails with exit 1 when --vars-file is not a JSON object',
        () async {
          final moldDir = Directory(p.join(workDir.path, 'mold'))..createSync();
          await writeCastableMold(directory: moldDir, name: 'demo_app');
          File(p.join(workDir.path, 'vars.json')).writeAsStringSync('[1, 2]');
          final errorMessages = <String>[];
          final runner = buildRunner(
            workingDirectory: workDir,
            onError: errorMessages.add,
          );

          final exitCode = await runner.run([
            'cast',
            'mold',
            '--output=out',
            '--vars-file=vars.json',
          ]);

          expect(exitCode, FoundryExitCode.userError.code);
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
          );

          final exitCode = await runner.run(['cast', 'mold', '--output=out']);

          expect(exitCode, FoundryExitCode.success.code);
          expect(gatherCalls, 1);
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
