import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_sync.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_test_support.dart';

Future<void> _writeFile(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

Future<Directory> _createPattern(Directory workDir) async {
  final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
  await _writeFile(
    pattern,
    '.foundry/pattern.yaml',
    'name: sync_pattern\n'
        'ignore:\n'
        '  - "**/*.tmp"\n',
  );
  await _writeFile(pattern, 'README.md', '# Hello {{ project_name }}\n');
  await _writeFile(pattern, 'lib/app.dart', 'void main() {}\n');
  await _writeFile(pattern, 'scratch.tmp', 'ignored');
  return pattern;
}

Future<Directory> _createMold(Directory workDir) async {
  final mold = Directory(p.join(workDir.path, 'existing_mold'))..createSync();
  await writeMoldPubspec(
    directory: mold,
    name: 'existing_mold',
    description: 'An existing Foundry mold.',
  );
  await _writeFile(
    mold,
    'variables.dart',
    '// custom author variables\n'
        "import 'package:foundry_core/foundry_core.dart';\n"
        '\n'
        'final moldVariables = FoundryVariableGroup(\n'
        '  variables: {\n'
        "    'project_name': FoundryStringVariable(\n"
        "      description: 'Project name',\n"
        '    ),\n'
        '  },\n'
        ');\n',
  );
  await Directory(p.join(mold.path, 'hooks')).create();
  await _writeFile(
    mold,
    'hooks/prepare.dart',
    '// custom prepare hook\n',
  );
  await _writeFile(
    mold,
    'template/README.md',
    'stale readme\n',
  );
  await _writeFile(
    mold,
    'template/orphan.txt',
    'orphan content\n',
  );
  await _writeFile(
    mold,
    'lib/custom.dart',
    '// custom mold package code\n',
  );
  return mold;
}

void main() {
  late Directory workDir;
  late Future<void> Function({
    required Directory stagedTemplate,
    required Directory moldDirectory,
    required bool force,
  }) originalCommit;
  late Future<PatternInspectionReport> Function(String patternPath)
      originalInspect;
  late MoldPubspec Function({
    required String yamlContent,
    required String sourcePath,
  }) originalParsePubspec;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_sync_');
    originalCommit = commitSyncedMoldTemplate;
    originalInspect = inspectPatternForSync;
    originalParsePubspec = parseMoldPubspecForSync;
  });

  tearDown(() {
    commitSyncedMoldTemplate = originalCommit;
    inspectPatternForSync = originalInspect;
    parseMoldPubspecForSync = originalParsePubspec;
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('syncMoldFromPattern', () {
    test('refreshes template files and preserves manual mold edits', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      final variablesBefore = await File(
        p.join(mold.path, 'variables.dart'),
      ).readAsString();
      final hookBefore = await File(
        p.join(mold.path, 'hooks', 'prepare.dart'),
      ).readAsString();
      final pubspecBefore = await File(
        p.join(mold.path, 'pubspec.yaml'),
      ).readAsString();
      final customLibBefore = await File(
        p.join(mold.path, 'lib', 'custom.dart'),
      ).readAsString();

      final synced = await syncMoldFromPattern(
        patternPath: pattern.path,
        moldDirectory: mold,
        tempParent: workDir,
      );

      expect(synced.path, mold.absolute.path);

      final readme = await File(
        p.join(mold.path, 'template', 'README.md'),
      ).readAsString();
      expect(readme, '{% raw %}# Hello {{ project_name }}\n{% endraw %}');
      expect(
        File(p.join(mold.path, 'template', 'lib', 'app.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(mold.path, 'template', 'scratch.tmp')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(mold.path, 'template', '.foundry')).existsSync(),
        isFalse,
      );

      // Without force, orphan template files are preserved.
      expect(
        File(p.join(mold.path, 'template', 'orphan.txt')).existsSync(),
        isTrue,
      );

      expect(
        await File(p.join(mold.path, 'variables.dart')).readAsString(),
        variablesBefore,
      );
      expect(
        await File(p.join(mold.path, 'hooks', 'prepare.dart')).readAsString(),
        hookBefore,
      );
      expect(
        await File(p.join(mold.path, 'pubspec.yaml')).readAsString(),
        pubspecBefore,
      );
      expect(
        await File(p.join(mold.path, 'lib', 'custom.dart')).readAsString(),
        customLibBefore,
      );
    });

    test('force replaces template and removes orphans', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);
      final variablesBefore = await File(
        p.join(mold.path, 'variables.dart'),
      ).readAsString();

      await syncMoldFromPattern(
        patternPath: pattern.path,
        moldDirectory: mold,
        force: true,
        tempParent: workDir,
      );

      expect(
        File(p.join(mold.path, 'template', 'orphan.txt')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(mold.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
      expect(
        await File(p.join(mold.path, 'variables.dart')).readAsString(),
        variablesBefore,
      );
      expect(
        File(p.join(mold.path, 'hooks', 'prepare.dart')).existsSync(),
        isTrue,
      );
    });

    test('creates template directory when missing', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);
      await Directory(p.join(mold.path, 'template')).delete(recursive: true);

      await syncMoldFromPattern(
        patternPath: pattern.path,
        moldDirectory: mold,
        tempParent: workDir,
      );

      expect(
        File(p.join(mold.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
    });

    test('rejects a path that is not a mold', () async {
      final pattern = await _createPattern(workDir);
      final notMold = Directory(p.join(workDir.path, 'random'))..createSync();
      await _writeFile(notMold, 'README.md', 'nope');

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: notMold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('is not a mold'),
          ),
        ),
      );
    });

    test('rejects a missing mold directory', () async {
      final pattern = await _createPattern(workDir);
      final missing = Directory(p.join(workDir.path, 'missing_mold'));

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: missing,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('rejects a mold path that is a symlink, not a directory', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);
      final linkPath = p.join(workDir.path, 'mold_link');
      Link(linkPath).createSync(mold.path);

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: Directory(linkPath),
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('is not a directory'),
          ),
        ),
      );
    });

    test('rejects a mold missing variables.dart', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);
      await File(p.join(mold.path, 'variables.dart')).delete();

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('variables.dart'),
          ),
        ),
      );
    });

    test('rejects an invalid mold pubspec', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);
      await File(p.join(mold.path, 'pubspec.yaml')).writeAsString(
        'name: broken\n',
      );

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('is not a mold'),
          ),
        ),
      );
    });

    test('rejects a mold pubspec with empty parse error messages', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      parseMoldPubspecForSync = ({
        required yamlContent,
        required sourcePath,
      }) {
        throw const MoldLoadException([
          MoldIssue(
            severity: MoldIssueSeverity.error,
            path: 'pubspec.yaml',
            message: '',
          ),
        ]);
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('invalid pubspec.yaml'),
          ),
        ),
      );
    });

    test('rejects a mold path equal to the pattern directory', () async {
      final pattern = await _createPattern(workDir);
      await writeMoldPubspec(
        directory: pattern,
        name: 'pattern_as_mold',
        description: 'Not a real sync target.',
      );
      await _writeFile(
        pattern,
        'variables.dart',
        "import 'package:foundry_core/foundry_core.dart';\n"
            'final moldVariables = FoundryVariableGroup(variables: {});\n',
      );

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: pattern,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('cannot be inside the pattern'),
          ),
        ),
      );
    });

    test('rejects an invalid pattern path', () async {
      final mold = await _createMold(workDir);
      final missingPattern = p.join(workDir.path, 'no_such_pattern');

      expect(
        () => syncMoldFromPattern(
          patternPath: missingPattern,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('invalid'),
          ),
        ),
      );
    });

    test('rejects a mold path inside the pattern', () async {
      final pattern = await _createPattern(workDir);
      final nestedMold = Directory(p.join(pattern.path, 'nested_mold'))
        ..createSync();
      await writeMoldPubspec(
        directory: nestedMold,
        name: 'nested_mold',
        description: 'Nested mold.',
      );
      await _writeFile(
        nestedMold,
        'variables.dart',
        "import 'package:foundry_core/foundry_core.dart';\n"
            'final moldVariables = FoundryVariableGroup(variables: {});\n',
      );

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: nestedMold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('cannot be inside the pattern'),
          ),
        ),
      );
    });

    test('cleans up staging after success', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      await syncMoldFromPattern(
        patternPath: pattern.path,
        moldDirectory: mold,
        tempParent: workDir,
      );

      final stagingDirs = workDir
          .listSync()
          .whereType<Directory>()
          .where((dir) => p.basename(dir.path).startsWith('foundry_mold_sync_'))
          .toList();
      expect(stagingDirs, isEmpty);
    });

    test('cleans up staging after commit failure', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      commitSyncedMoldTemplate = ({
        required stagedTemplate,
        required moldDirectory,
        required force,
      }) async {
        throw const FileSystemException('simulated commit failure');
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(isA<MoldSyncException>()),
      );

      final stagingDirs = workDir
          .listSync()
          .whereType<Directory>()
          .where((dir) => p.basename(dir.path).startsWith('foundry_mold_sync_'))
          .toList();
      expect(stagingDirs, isEmpty);
    });

    test('wraps FileSystemException from commit with a path', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      commitSyncedMoldTemplate = ({
        required stagedTemplate,
        required moldDirectory,
        required force,
      }) async {
        throw const FileSystemException('Permission denied', '/tmp/blocked');
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Failed to sync mold'),
              contains('Permission denied'),
              contains('/tmp/blocked'),
            ),
          ),
        ),
      );
    });

    test('wraps FileSystemException from commit with a null path', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      commitSyncedMoldTemplate = ({
        required stagedTemplate,
        required moldDirectory,
        required force,
      }) async {
        throw const FileSystemException('Permission denied');
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Failed to sync mold'),
              contains('Permission denied'),
              isNot(contains('()')),
            ),
          ),
        ),
      );
    });

    test('maps injectable MoldSyncException from commit', () async {
      final pattern = await _createPattern(workDir);
      final mold = await _createMold(workDir);

      commitSyncedMoldTemplate = ({
        required stagedTemplate,
        required moldDirectory,
        required force,
      }) async {
        throw const MoldSyncException('commit blocked');
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: pattern.path,
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            'commit blocked',
          ),
        ),
      );
    });

    test('uses injectable inspect failure messaging', () async {
      final mold = await _createMold(workDir);
      inspectPatternForSync = (patternPath) async {
        return PatternInspectionReport(
          rootPath: patternPath,
          issues: const [
            PatternIssue(
              severity: PatternIssueSeverity.error,
              path: 'pattern',
              message: '',
            ),
          ],
        );
      };

      expect(
        () => syncMoldFromPattern(
          patternPath: p.join(workDir.path, 'pattern'),
          moldDirectory: mold,
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldSyncException>().having(
            (error) => error.message,
            'message',
            contains('could not be inspected'),
          ),
        ),
      );
    });
  });
}
