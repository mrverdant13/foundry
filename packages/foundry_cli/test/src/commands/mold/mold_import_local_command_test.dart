import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_import_local_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_import_');
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
        MoldImportLocalCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  group('MoldImportLocalCommand', () {
    test('copies the source mold to ./<name>/ under the working directory',
        () async {
      final sourceDir = Directory(p.join(workDir.path, 'source'))..createSync();
      await writeImportSourceMold(directory: sourceDir, name: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['local', '--path=${sourceDir.path}']);

      expect(exitCode, FoundryExitCode.success.code);
      final destination = Directory(p.join(destParent.path, 'greeter'));
      expect(destination.existsSync(), isTrue);
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(infoMessages, contains(contains(destination.path)));
    });

    test('fails with a user error when the destination exists without force',
        () async {
      final sourceDir = Directory(p.join(workDir.path, 'source'))..createSync();
      await writeImportSourceMold(directory: sourceDir, name: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      Directory(p.join(destParent.path, 'greeter')).createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['local', '--path=${sourceDir.path}']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('already exists')));
    });

    test('overwrites the destination when --force is passed', () async {
      final sourceDir = Directory(p.join(workDir.path, 'source'))..createSync();
      await writeImportSourceMold(directory: sourceDir, name: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final existing = Directory(p.join(destParent.path, 'greeter'))
        ..createSync();
      File(p.join(existing.path, 'stale.txt')).createSync();
      final runner = buildRunner(workingDirectory: destParent);

      final exitCode = await runner.run(
        ['local', '--path=${sourceDir.path}', '--force'],
      );

      expect(exitCode, FoundryExitCode.success.code);
      final destination = Directory(p.join(destParent.path, 'greeter'));
      expect(File(p.join(destination.path, 'stale.txt')).existsSync(), isFalse);
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('fails with a user error when the source does not exist', () async {
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(
        ['local', '--path=${p.join(workDir.path, 'does_not_exist')}'],
      );

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test('requires --path', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['local']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
