import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_inspect_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show
        Logger,
        PatternInspectionReport,
        PatternIssue,
        PatternIssueSeverity,
        patternMarkerRelativePath;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_pattern_inspect_');
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
    PatternInspector? inspectPatternFn,
  }) {
    return CommandRunner<int>('foundry', 'test runner')
      ..addCommand(
        PatternInspectCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
          inspectPatternFn: inspectPatternFn,
        ),
      );
  }

  Future<void> writeInspectablePattern({
    required Directory directory,
    String? name,
  }) async {
    await File(p.join(directory.path, 'README.md')).writeAsString('# Pattern');
    await Directory(p.join(directory.path, 'lib')).create();
    await File(p.join(directory.path, 'lib', 'main.dart')).writeAsString(
      'void main() {}',
    );
    if (name == null) {
      return;
    }
    await Directory(p.join(directory.path, '.foundry')).create();
    await File(p.join(directory.path, patternMarkerRelativePath)).writeAsString(
      '''
name: "$name"
ignore:
  - build/**
''',
    );
    await Directory(p.join(directory.path, 'build')).create();
    await File(p.join(directory.path, 'build', 'out.txt')).writeAsString('x');
  }

  group('PatternInspectCommand', () {
    test('defaults workingDirectory to Directory.current', () {
      final command = PatternInspectCommand(logger: Logger());
      expect(command.workingDirectory.path, Directory.current.path);
    });

    test('reports success for a valid pattern in the working directory',
        () async {
      await writeInspectablePattern(directory: workDir, name: 'demo_pattern');
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains('Pattern: demo_pattern'));
      expect(infoMessages, contains(contains('Path:')));
      expect(infoMessages, contains('Marker: yes'));
      expect(infoMessages, contains(contains('Files:')));
      expect(infoMessages, contains('Ignore globs:'));
      expect(infoMessages, contains('  - build/**'));
      expect(infoMessages, contains('Top-level entries:'));
      expect(infoMessages, contains('Ignored paths:'));
      expect(infoMessages, contains('  - build/out.txt'));
    });

    test('defaults to the working directory when no path is given', () async {
      await writeInspectablePattern(directory: workDir);
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains('Pattern: (unnamed)'));
      expect(infoMessages, contains('Marker: no'));
      expect(
        infoMessages,
        contains('Path: ${Directory(workDir.path).absolute.path}'),
      );
    });

    test('inspects a pattern at an explicit relative path', () async {
      final patternDir = Directory(p.join(workDir.path, 'my_pattern'))
        ..createSync();
      await writeInspectablePattern(
        directory: patternDir,
        name: 'my_pattern',
      );
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['inspect', 'my_pattern']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains('Pattern: my_pattern'));
      expect(
        infoMessages,
        contains('Path: ${patternDir.absolute.path}'),
      );
    });

    test('fails with a user error when the pattern path does not exist',
        () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['inspect', 'does_not_exist']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('does not exist')));
    });

    test('fails with a user error when the path is not a directory', () async {
      final file = File(p.join(workDir.path, 'not_a_dir.txt'))
        ..writeAsStringSync('x');
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['inspect', 'not_a_dir.txt']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('not a directory')));
      expect(errorMessages, contains(contains(file.path)));
    });

    test('rejects more than one positional argument', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['inspect', 'a', 'b']),
        throwsA(isA<UsageException>()),
      );
    });

    test('prints warnings and still reports when the pattern is valid',
        () async {
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
        inspectPatternFn: (patternPath) async => PatternInspectionReport(
          rootPath: patternPath,
          name: 'warned_pattern',
          hasMarker: true,
          ignoreGlobs: const [],
          fileCount: 0,
          topLevelEntries: const [],
          ignoredPaths: const [],
          issues: [
            PatternIssue(
              severity: PatternIssueSeverity.warning,
              path: patternPath,
              message: 'Optional marker is incomplete.',
            ),
          ],
        ),
      );

      final exitCode = await runner.run(['inspect']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        infoMessages,
        contains(contains('[WARN]')),
      );
      expect(
        infoMessages,
        contains(contains('Optional marker is incomplete.')),
      );
      expect(infoMessages, contains('Pattern: warned_pattern'));
      expect(infoMessages, contains('Ignore globs: (none)'));
      expect(infoMessages, contains('Top-level entries: (none)'));
      expect(infoMessages, contains('Ignored paths: (none)'));
    });
  });
}
