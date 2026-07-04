import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_init_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_init_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  CommandRunner<int> buildRunner({
    required Directory workingDirectory,
    void Function(String message)? onInfo,
    void Function(String message)? onError,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        MoldInitCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  group('MoldInitCommand', () {
    test('scaffolds the expected tree using --name', () async {
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=flutter_app']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(workDir.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(workDir.path, 'variables.dart')).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(workDir.path, 'template')).existsSync(), isTrue);
      expect(Directory(p.join(workDir.path, 'hooks')).existsSync(), isTrue);
      expect(infoMessages, contains(contains('flutter_app')));
    });

    test('defaults the mold name to the working directory name', () async {
      final namedDir = Directory(p.join(workDir.path, 'my_mold'))..createSync();
      final runner = buildRunner(workingDirectory: namedDir);

      final exitCode = await runner.run(['init']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(namedDir.path, 'pubspec.yaml')).readAsStringSync(),
        contains('name: my_mold'),
      );
    });

    test('fails with a user error for an invalid --name', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=Invalid-Name']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Invalid mold name')));
      expect(
        File(p.join(workDir.path, 'pubspec.yaml')).existsSync(),
        isFalse,
      );
    });

    test('fails with a user error when a mold already exists', () async {
      File(p.join(workDir.path, 'pubspec.yaml')).createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=flutter_app']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('already exists')));
    });
  });
}
