import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_init_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, patternMarkerRelativePath;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_pattern_init_');
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
        PatternInitCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  group('PatternInitCommand', () {
    test('scaffolds the expected files using --name', () async {
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=demo_pattern']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(workDir.path, patternMarkerRelativePath)).existsSync(),
        isTrue,
      );
      expect(File(p.join(workDir.path, 'README.md')).existsSync(), isTrue);
      expect(infoMessages, contains(contains('demo_pattern')));
    });

    test('trims --name before logging and writing', () async {
      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=  padded_name  ']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        infoMessages,
        contains(contains('Scaffolded pattern "padded_name"')),
      );
      expect(
        File(p.join(workDir.path, patternMarkerRelativePath))
            .readAsStringSync(),
        contains('name: padded_name'),
      );
      expect(
        File(p.join(workDir.path, 'README.md')).readAsStringSync(),
        contains('# padded_name'),
      );
    });

    test('defaults the pattern name to the working directory name', () async {
      final namedDir = Directory(p.join(workDir.path, 'my_pattern'))
        ..createSync();
      final runner = buildRunner(workingDirectory: namedDir);

      final exitCode = await runner.run(['init']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(namedDir.path, patternMarkerRelativePath))
            .readAsStringSync(),
        contains('name: my_pattern'),
      );
    });

    test('fails with a user error for an empty --name', () async {
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=   ']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Invalid pattern name')));
      expect(
        File(p.join(workDir.path, patternMarkerRelativePath)).existsSync(),
        isFalse,
      );
      expect(File(p.join(workDir.path, 'README.md')).existsSync(), isFalse);
    });

    test('fails with a user error when a pattern already exists', () async {
      File(p.join(workDir.path, 'README.md')).createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: workDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run(['init', '--name=demo_pattern']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('already exists')));
    });

    test('exits 0 after scaffolding an empty directory', () async {
      final runner = buildRunner(workingDirectory: workDir);

      final exitCode = await runner.run(['init', '--name=empty_dir_pattern']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(
        File(p.join(workDir.path, patternMarkerRelativePath)).existsSync(),
        isTrue,
      );
      expect(File(p.join(workDir.path, 'README.md')).existsSync(), isTrue);
    });
  });
}
