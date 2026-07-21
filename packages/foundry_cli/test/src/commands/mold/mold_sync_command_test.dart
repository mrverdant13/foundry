import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_sync_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, deriveMoldFromPattern, patternMarkerRelativePath;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_sync_');
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
        MoldSyncCommand(
          logger: Logger(onInfo: onInfo, onError: onError),
          workingDirectory: workingDirectory,
        ),
      );
  }

  Future<Directory> writePattern({
    required String relativePath,
    String name = 'demo_pattern',
    String readmeBody = '# demo_pattern\n\nHello {{ project_name }}\n',
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
    await File(p.join(patternDir.path, 'README.md')).writeAsString(readmeBody);
    await File(p.join(patternDir.path, 'lib', 'app.dart'))
        .create(recursive: true)
        .then((file) => file.writeAsString('void main() {}\n'));
    await File(p.join(patternDir.path, 'scratch.tmp')).writeAsString('ignored');
    return patternDir;
  }

  Future<Directory> writeMold({
    required String relativePath,
    required String patternRelativePath,
  }) async {
    final patternDir = Directory(p.join(workDir.path, patternRelativePath));
    final moldDir = Directory(p.join(workDir.path, relativePath));
    await deriveMoldFromPattern(
      patternPath: patternDir.path,
      destination: moldDir,
    );
    return moldDir;
  }

  group('MoldSyncCommand', () {
    test('syncs template/ and preserves variables.dart', () async {
      await writePattern(relativePath: 'pattern');
      final moldDir = await writeMold(
        relativePath: 'mold',
        patternRelativePath: 'pattern',
      );

      final variablesPath = p.join(moldDir.path, 'variables.dart');
      const customVariables = '// custom author edits\n'
          "import 'package:foundry_core/foundry_core.dart';\n\n"
          'final variables = FoundryVariableGroup(variables: []);\n';
      await File(variablesPath).writeAsString(customVariables);

      await File(p.join(workDir.path, 'pattern', 'README.md')).writeAsString(
        '# demo_pattern\n\nUpdated {{ project_name }}\n',
      );
      await File(p.join(workDir.path, 'pattern', 'lib', 'new_file.dart'))
          .create(recursive: true)
          .then((file) => file.writeAsString('class NewFile {}\n'));

      final infoMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: moldDir,
        onInfo: infoMessages.add,
      );

      final exitCode = await runner.run([
        'sync',
        '--pattern=${p.join(workDir.path, 'pattern')}',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      expect(File(variablesPath).readAsStringSync(), customVariables);
      expect(
        File(p.join(moldDir.path, 'template', 'README.md')).readAsStringSync(),
        contains('Updated'),
      );
      expect(
        File(p.join(moldDir.path, 'template', 'lib', 'new_file.dart'))
            .existsSync(),
        isTrue,
      );
      expect(infoMessages, contains(contains(moldDir.path)));
    });

    test('exits 1 when the mold directory is missing mold files', () async {
      await writePattern(relativePath: 'pattern');
      final emptyMold = Directory(p.join(workDir.path, 'not_a_mold'))
        ..createSync();
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: emptyMold,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run([
        'sync',
        '--pattern=${p.join(workDir.path, 'pattern')}',
      ]);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
      expect(errorMessages.first, contains('not a mold'));
    });

    test('exits 1 when the pattern path is missing', () async {
      await writePattern(relativePath: 'pattern');
      final moldDir = await writeMold(
        relativePath: 'mold',
        patternRelativePath: 'pattern',
      );
      final errorMessages = <String>[];
      final runner = buildRunner(
        workingDirectory: moldDir,
        onError: errorMessages.add,
      );

      final exitCode = await runner.run([
        'sync',
        '--pattern=missing_pattern',
      ]);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, isNotEmpty);
    });

    test('requires --pattern', () async {
      final runner = buildRunner(workingDirectory: workDir);

      await expectLater(
        runner.run(['sync']),
        throwsA(isA<UsageException>()),
      );
    });

    test('with --force removes orphan template files', () async {
      await writePattern(relativePath: 'pattern');
      final moldDir = await writeMold(
        relativePath: 'mold',
        patternRelativePath: 'pattern',
      );

      final orphan = File(p.join(moldDir.path, 'template', 'orphan.txt'))
        ..writeAsStringSync('orphan');
      final variablesPath = p.join(moldDir.path, 'variables.dart');
      final variablesBefore = File(variablesPath).readAsStringSync();

      final runner = buildRunner(workingDirectory: moldDir);
      final exitCode = await runner.run([
        'sync',
        '--pattern=${p.join(workDir.path, 'pattern')}',
        '--force',
      ]);

      expect(exitCode, FoundryExitCode.success.code);
      expect(orphan.existsSync(), isFalse);
      expect(File(variablesPath).readAsStringSync(), variablesBefore);
    });
  });
}
