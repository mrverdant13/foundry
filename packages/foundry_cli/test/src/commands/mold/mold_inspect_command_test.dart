import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_inspect_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
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
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        MoldInspectCommand(
          logger: Logger(onInfo: onInfo, onWarn: onWarn, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  group('MoldInspectCommand', () {
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
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('template')));
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
      expect(warnMessages, contains(contains('variables')));
      expect(infoMessages, contains(contains('demo_app')));
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
