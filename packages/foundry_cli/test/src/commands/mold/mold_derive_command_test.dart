import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_derive_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, patternMarkerRelativePath;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_derive_');
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
        MoldDeriveCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  Future<Directory> writePattern({
    required String relativePath,
    String name = 'demo_pattern',
  }) async {
    final patternDir = Directory(p.join(workDir.path, relativePath))
      ..createSync(recursive: true);
    await File(p.join(patternDir.path, patternMarkerRelativePath))
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(
            'name: "$name"\n'
            'ignore:\n'
            '  - "**/*.tmp"\n'
            '  - ".dart_tool/**"\n'
            '  - ".git/**"\n'
            '  - "build/**"\n',
          ),
        );
    await File(p.join(patternDir.path, 'README.md')).writeAsString(
      '# $name\n\nHello {{ project_name }}\n',
    );
    await File(p.join(patternDir.path, 'lib', 'app.dart'))
        .create(recursive: true)
        .then((file) => file.writeAsString('void main() {}\n'));
    await File(p.join(patternDir.path, 'scratch.tmp')).writeAsString('ignored');
    return patternDir;
  }

  group('MoldDeriveCommand', () {
    test('derives a mold tree that depends on foundry_core', () async {
      await writePattern(relativePath: 'pattern');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run([
        'derive',
        '--pattern=pattern',
        '--output=out_mold',
      ]);

      expect(exitCode, FoundryExitCode.success.code);

      final moldDir = Directory(p.join(workDir.path, 'out_mold'));
      expect(moldDir.existsSync(), isTrue);
      expect(File(p.join(moldDir.path, 'pubspec.yaml')).existsSync(), isTrue);
      expect(File(p.join(moldDir.path, 'variables.dart')).existsSync(), isTrue);
      expect(Directory(p.join(moldDir.path, 'hooks')).existsSync(), isTrue);
      expect(
        File(p.join(moldDir.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'template', 'lib', 'app.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'template', 'scratch.tmp')).existsSync(),
        isFalse,
      );

      final pubspec =
          File(p.join(moldDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('name: demo_pattern'));
      expect(pubspec, contains('foundry_core:'));

      expect(infoMessages, contains(contains(moldDir.path)));
    });

    test('fails without --force when the destination already exists', () async {
      await writePattern(relativePath: 'pattern');
      final destination = Directory(p.join(workDir.path, 'out_mold'))
        ..createSync();
      File(p.join(destination.path, 'stale.txt')).writeAsStringSync('stale');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run([
        'derive',
        '--pattern=pattern',
        '--output=out_mold',
      ]);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('already exists')));
      expect(
        File(p.join(destination.path, 'stale.txt')).existsSync(),
        isTrue,
      );
    });

    test('overwrites the destination when --force is passed', () async {
      await writePattern(relativePath: 'pattern');
      final destination = Directory(p.join(workDir.path, 'out_mold'))
        ..createSync();
      File(p.join(destination.path, 'stale.txt')).writeAsStringSync('stale');
      final runner = buildRunner(workingDirectory: workDir);

      final exitCode = await runner.run([
        'derive',
        '--pattern=pattern',
        '--output=out_mold',
        '--force',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(destination.path, 'stale.txt')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('fails with a user error when the pattern path is missing', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run([
        'derive',
        '--pattern=missing_pattern',
        '--output=out_mold',
      ]);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
      expect(
        Directory(p.join(workDir.path, 'out_mold')).existsSync(),
        isFalse,
      );
    });

    test('requires --pattern', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['derive', '--output=out_mold']),
        throwsA(isA<UsageException>()),
      );
    });

    test('defaults --output to the working directory', () async {
      final emptyCwd = Directory(p.join(workDir.path, 'empty_cwd'))
        ..createSync();
      await writePattern(relativePath: 'pattern');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: emptyCwd,
        onInfo: infoMessages.add,
      );

      // cwd always exists as a directory, so --force is required to write
      // into it (same contract as deriveMoldFromPattern).
      final exitCode = await runner.run([
        'derive',
        '--pattern=${p.join(workDir.path, 'pattern')}',
        '--force',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(emptyCwd.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(infoMessages, contains(contains(emptyCwd.path)));
    });
  });
}
