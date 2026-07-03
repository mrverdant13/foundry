import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<ProcessResult> _git(List<String> args, {required String cwd}) {
  return Process.run('git', args, workingDirectory: cwd);
}

/// Initializes a local git repository at [repoDir] with a mold at
/// `<repoDir>/<subPath>` and commits it, so tests can clone from a `file://`
/// remote without hitting the network.
Future<void> _initMoldRepo(
  Directory repoDir, {
  required String moldName,
  String subPath = '.',
}) async {
  final moldDir =
      subPath == '.' ? repoDir : Directory(p.join(repoDir.path, subPath))
        ..createSync(recursive: true);

  File(p.join(moldDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $moldName
description: A git-imported mold fixture
version: 0.0.1
''');
  Directory(p.join(moldDir.path, 'template')).createSync();
  File(p.join(moldDir.path, 'template', 'README.md'))
      .writeAsStringSync('# $moldName\n');

  await _git(['init', '--quiet'], cwd: repoDir.path);
  await _git(
    ['-c', 'user.email=test@example.com', '-c', 'user.name=Test', 'add', '-A'],
    cwd: repoDir.path,
  );
  final commitResult = await _git(
    [
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Test',
      'commit',
      '--quiet',
      '-m',
      'Initial commit',
    ],
    cwd: repoDir.path,
  );
  if (commitResult.exitCode != 0) {
    fail(
      'Failed to set up git fixture repo: '
      '${commitResult.stdout}${commitResult.stderr}',
    );
  }
}

int _tempImportDirCount() {
  return Directory.systemTemp
      .listSync()
      .whereType<Directory>()
      .where((dir) => p.basename(dir.path).startsWith('foundry_mold_import_'))
      .length;
}

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_git_import_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('importMoldFromGit', () {
    test('clones a local repo and copies the mold to the destination',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final tempDirCountBefore = _tempImportDirCount();

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        destinationParent: destinationParent,
      );

      expect(destination.path, p.join(destinationParent.path, 'greeter'));
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(destination.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
      expect(_tempImportDirCount(), tempDirCountBefore);
    });

    test('does not copy the cloned repository VCS metadata', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        destinationParent: destinationParent,
      );

      expect(Directory(p.join(destination.path, '.git')).existsSync(), isFalse);
    });

    test('descends into the given path when the mold is in a subdirectory',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'nested', subPath: 'molds/api');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        path: 'molds/api',
        destinationParent: destinationParent,
      );

      expect(destination.path, p.join(destinationParent.path, 'nested'));
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('fails when the given path does not exist in the repository',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final tempDirCountBefore = _tempImportDirCount();

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          path: 'does_not_exist',
          destinationParent: destinationParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('was not found'),
          ),
        ),
      );
      expect(_tempImportDirCount(), tempDirCountBefore);
    });

    test('fails when the given path is absolute', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();
      final outsideDir = Directory(p.join(workDir.path, 'outside'))
        ..createSync();
      File(p.join(outsideDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: outside
description: should not be importable via an absolute path
version: 0.0.1
''');

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          path: outsideDir.path,
          destinationParent: destinationParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('must be relative'),
          ),
        ),
      );
    });

    test('fails when the given path escapes the cloned repository', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          path: '../outside',
          destinationParent: destinationParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('resolves outside'),
          ),
        ),
      );
    });

    test('fails when the clone url is invalid', () async {
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      await expectLater(
        importMoldFromGit(
          gitUrl: p.join(workDir.path, 'does_not_exist'),
          destinationParent: destinationParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('Failed to clone'),
          ),
        ),
      );
    });

    test('fails when destination exists and force is false', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();
      Directory(p.join(destinationParent.path, 'greeter')).createSync();

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          destinationParent: destinationParent,
        ),
        throwsA(isA<MoldImportException>()),
      );
    });
  });
}
