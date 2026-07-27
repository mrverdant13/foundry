import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/cast_session_describe.dart';
import 'package:foundry_cli/src/commands/mold/mold_inspect_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_inspect_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  CommandRunner<int> buildRunner({
    required Directory workingDirectory,
    void Function(String message)? onInfo,
    void Function(String message)? onWarn,
    void Function(String message)? onError,
    MoldInspectDescribeLauncher? launchDescribeSession,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        MoldInspectCommand(
          logger: Logger(onInfo: onInfo, onWarn: onWarn, onError: onError),
          workingDirectory: workingDirectory,
          launchDescribeSession: launchDescribeSession ??
              ({required moldPath}) async {
                return const MoldCastSessionDescribeSuccess(
                  variables: [],
                  exitCode: 0,
                );
              },
        ),
      );
  }

  group('MoldInspectCommand', () {
    test('describes declared variables rather than cast-time visibility', () {
      final command = MoldInspectCommand(logger: Logger());

      expect(command.description, contains('declared variable'));
      expect(command.description, contains('cast-time visibility'));
    });

    test('reports success for a valid mold in the working directory', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('demo_app')));
    });

    test('inspects a mold at an explicit relative path', () async {
      final moldDir = Directory(p.join(workDir.path, 'my_mold'))..createSync();
      await writeInspectableMold(directory: moldDir, name: 'my_mold');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect', 'my_mold']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('my_mold')));
    });

    test('fails with a user error when the template directory is missing',
        () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      Directory(p.join(workDir.path, 'template')).deleteSync();
      final errorMessages = <String>[];
      var describeCalled = false;
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          describeCalled = true;
          return const MoldCastSessionDescribeSuccess(
            variables: [],
            exitCode: 0,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('template')));
      expect(describeCalled, isFalse);
    });

    test('fails with a user error when the mold path does not exist', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['inspect', 'does_not_exist']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test('reports warnings for present optional hooks', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final hooksDir = Directory(p.join(workDir.path, 'hooks'))..createSync();
      await File(p.join(hooksDir.path, 'shape.dart')).writeAsString('//');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('[WARN]')));
      expect(infoMessages, contains(contains('shape')));
      expect(infoMessages, contains(contains('demo_app')));
    });

    test('reports warnings for an empty variable group', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      await File(p.join(workDir.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(variables: {});
''');
      final warnMessages = <String>[];
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onWarn: warnMessages.add,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('variables')));
      expect(infoMessages, contains(contains('demo_app')));
      expect(warnMessages, isEmpty);
    });

    test('reports live variable metadata that serialize-stripping drops',
        () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final infoMessages = <String>[];
      String? describedMoldPath;
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          describedMoldPath = moldPath;
          return const MoldCastSessionDescribeSuccess(
            variables: [
              MoldVariableDescription(
                key: 'project_name',
                kind: 'string',
                label: 'Project name',
                description: 'UNIQUE_DESC_PROJECT_NAME',
                help: 'UNIQUE_HELP_PROJECT_NAME',
                placeholder: 'UNIQUE_PLACEHOLDER',
              ),
              MoldVariableDescription(
                key: 'project_type',
                kind: 'single-choice',
                label: 'Project type',
                options: [
                  MoldVariableOptionDescription(
                    value: 'app',
                    label: 'LABEL_app',
                  ),
                  MoldVariableOptionDescription(
                    value: 'package',
                    label: 'LABEL_package',
                  ),
                ],
              ),
            ],
            exitCode: 0,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(describedMoldPath, workDir.path);
      expect(infoMessages, contains('Declared variables:'));
      expect(
        infoMessages,
        contains(contains('UNIQUE_DESC_PROJECT_NAME')),
      );
      expect(
        infoMessages,
        contains(contains('UNIQUE_HELP_PROJECT_NAME')),
      );
      expect(
        infoMessages,
        contains(contains('UNIQUE_PLACEHOLDER')),
      );
      expect(infoMessages, contains(contains('LABEL_app')));
      expect(infoMessages, contains(contains('LABEL_package')));
      expect(infoMessages, contains(contains('demo_app')));
    });

    test('logs nested object fields and values item schemas', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          return const MoldCastSessionDescribeSuccess(
            variables: [
              MoldVariableDescription(
                key: 'author',
                kind: 'object',
                label: 'Author',
                fields: [
                  MoldVariableDescription(
                    key: 'name',
                    kind: 'string',
                    label: 'Author name',
                    help: 'NESTED_HELP',
                  ),
                ],
              ),
              MoldVariableDescription(
                key: 'items',
                kind: 'values',
                label: 'Items',
                item: MoldVariableDescription(
                  key: 'item',
                  kind: 'string',
                  label: 'Item',
                  placeholder: 'ITEM_PLACEHOLDER',
                ),
              ),
            ],
            exitCode: 0,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(contains('fields:')));
      expect(infoMessages, contains(contains('NESTED_HELP')));
      expect(infoMessages, contains(contains('item:')));
      expect(infoMessages, contains(contains('ITEM_PLACEHOLDER')));
    });

    test('fails when the describe session returns a cast success payload',
        () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          return const MoldCastSessionLaunchSuccess(
            artifactCount: 0,
            vars: {},
            writtenFilePaths: [],
            outputDirectory: '',
            exitCode: 0,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.internalError.code);
      expect(
        errorMessages,
        contains(contains('unexpected cast session result')),
      );
    });

    test('does not write cast state while reporting variables', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: (_) {},
        launchDescribeSession: ({required moldPath}) async {
          return const MoldCastSessionDescribeSuccess(
            variables: [
              MoldVariableDescription(
                key: 'project_name',
                kind: 'string',
                label: 'Project name',
                help: 'LIVE_HELP',
              ),
            ],
            exitCode: 0,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(workDir.path, '.foundry', 'last_cast.json')).existsSync(),
        isFalse,
      );
    });

    test('surfaces describe-session failures with their exit codes', () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          return const MoldCastSessionLaunchFailure(
            kind: 'resolve',
            message: 'dart pub get failed: boom',
            exitCode: 1,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('dart pub get failed')));
    });

    test('preserves internal exit codes from describe-session failures',
        () async {
      await writeInspectableMold(directory: workDir, name: 'demo_app');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
        launchDescribeSession: ({required moldPath}) async {
          return MoldCastSessionLaunchFailure(
            kind: 'internal',
            message: 'Session result payload was not valid JSON.',
            exitCode: FoundryExitCode.internalError.code,
          );
        },
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.internalError.code);
      expect(errorMessages, contains(contains('not valid JSON')));
    });

    test('rejects more than one positional argument', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['inspect', 'a', 'b']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
