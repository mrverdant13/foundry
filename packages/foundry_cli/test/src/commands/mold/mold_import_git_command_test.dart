import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_import_git_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_command_test_support.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_import_git_');
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
        MoldImportGitCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  group('MoldImportGitCommand', () {
    test('clones the repository and copies the mold to ./<name>/', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await initMoldGitRepo(repoDir, moldName: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(
        ['git', '--git-url=${Uri.file(repoDir.path)}'],
      );

      expect(exitCode, FoundryExitCode.success.code);
      final destination = Directory(p.join(destParent.path, 'greeter'));
      expect(destination.existsSync(), isTrue);
      expect(infoMessages, contains(contains(destination.path)));
    });

    test('descends into --path when the mold is in a subdirectory', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await initMoldGitRepo(
        repoDir,
        moldName: 'nested',
        subPath: 'molds/api',
      );
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run([
        'git',
        '--git-url=${Uri.file(repoDir.path)}',
        '--path=molds/api',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      final destination = Directory(p.join(destParent.path, 'nested'));
      expect(destination.existsSync(), isTrue);
      expect(infoMessages, contains(contains(destination.path)));
    });

    test('overwrites the destination when --force is passed', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await initMoldGitRepo(repoDir, moldName: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final existing = Directory(p.join(destParent.path, 'greeter'))
        ..createSync();
      File(p.join(existing.path, 'stale.txt')).createSync();
      final runner = buildRunner(workingDirectory: destParent);

      final exitCode = await runner.run([
        'git',
        '--git-url=${Uri.file(repoDir.path)}',
        '--force',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      final destination = Directory(p.join(destParent.path, 'greeter'));
      expect(File(p.join(destination.path, 'stale.txt')).existsSync(), isFalse);
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('fails with a user error when the clone fails', () async {
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(
        ['git', '--git-url=${p.join(workDir.path, 'does_not_exist')}'],
      );

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test('fails with a user error when the destination exists without force',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await initMoldGitRepo(repoDir, moldName: 'greeter');
      final destParent = Directory(p.join(workDir.path, 'dest'))..createSync();
      Directory(p.join(destParent.path, 'greeter')).createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: destParent,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(
        ['git', '--git-url=${Uri.file(repoDir.path)}'],
      );

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('already exists')));
    });

    test('requires --git-url', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['git']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
