import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_git_import.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<ProcessResult> _git(List<String> args, {required String cwd}) {
  return Process.run('git', args, workingDirectory: cwd);
}

/// Initializes a local git repository at [repoDir] with a mold at
/// `<repoDir>/<subPath>` and commits it, so tests can clone from a `file://`
/// remote without hitting the network.
///
/// When [siblingPath] is set, also writes a sibling file outside the mold
/// subtree so sparse-checkout coverage can assert that path is omitted.
Future<void> _initMoldRepo(
  Directory repoDir, {
  required String moldName,
  String subPath = '.',
  String? siblingPath,
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

  if (siblingPath != null) {
    File(p.join(repoDir.path, siblingPath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('sibling content that should not be checked out\n');
  }

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

void main() {
  late Directory workDir;
  late Directory tempParent;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_git_import_');
    tempParent = Directory(p.join(workDir.path, 'tmp'))..createSync();
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

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        destinationParent: destinationParent,
        tempParent: tempParent,
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
      expect(tempParent.listSync(), isEmpty);
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
      await _initMoldRepo(
        repoDir,
        moldName: 'nested',
        subPath: 'molds/api',
        siblingPath: 'other/large.txt',
      );
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        path: 'molds/api',
        destinationParent: destinationParent,
        tempParent: tempParent,
      );

      expect(destination.path, p.join(destinationParent.path, 'nested'));
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(tempParent.listSync(), isEmpty);
    });

    test('sparse-checkouts only the requested subdirectory path', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(
        repoDir,
        moldName: 'nested',
        subPath: 'molds/api',
        siblingPath: 'other/large.txt',
      );
      final cloneDir = Directory(p.join(workDir.path, 'clone'))..createSync();

      await cloneMoldRepository(
        gitUrl: Uri.file(repoDir.path).toString(),
        destination: cloneDir,
        path: 'molds/api',
      );

      expect(
        File(p.join(cloneDir.path, 'molds', 'api', 'pubspec.yaml'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(cloneDir.path, 'other', 'large.txt')).existsSync(),
        isFalse,
      );
      expect(Directory(p.join(cloneDir.path, 'other')).existsSync(), isFalse);
    });

    test('full shallow clone keeps sibling paths when path is omitted',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(
        repoDir,
        moldName: 'greeter',
        siblingPath: 'other/large.txt',
      );
      final cloneDir = Directory(p.join(workDir.path, 'clone'))..createSync();

      await cloneMoldRepository(
        gitUrl: Uri.file(repoDir.path).toString(),
        destination: cloneDir,
      );

      expect(
        File(p.join(cloneDir.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(cloneDir.path, 'other', 'large.txt')).existsSync(),
        isTrue,
      );
    });

    test('fails when the given path does not exist in the repository',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          path: 'does_not_exist',
          destinationParent: destinationParent,
          tempParent: tempParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('was not found'),
          ),
        ),
      );
      expect(tempParent.listSync(), isEmpty);
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

    test(
        'fails when the cloned mold name would escape the destination '
        'parent', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      File(p.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: ../escaped
description: A mold name attempting a path traversal
version: 0.0.1
''');
      Directory(p.join(repoDir.path, 'template')).createSync();
      await _git(['init', '--quiet'], cwd: repoDir.path);
      await _git(
        [
          '-c',
          'user.email=test@example.com',
          '-c',
          'user.name=Test',
          'add',
          '-A',
        ],
        cwd: repoDir.path,
      );
      await _git(
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
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      await expectLater(
        importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          destinationParent: destinationParent,
          tempParent: tempParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('is not a valid destination directory name'),
          ),
        ),
      );
      expect(
        Directory(p.join(workDir.path, 'escaped')).existsSync(),
        isFalse,
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

    test('treats an empty path like an omitted path', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      final destination = await importMoldFromGit(
        gitUrl: Uri.file(repoDir.path).toString(),
        path: '',
        destinationParent: destinationParent,
        tempParent: tempParent,
      );

      expect(destination.path, p.join(destinationParent.path, 'greeter'));
    });

    test('defaults destinationParent to the process cwd', () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(repoDir, moldName: 'greeter');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();
      final previousCwd = Directory.current;
      Directory.current = destinationParent;
      try {
        final destination = await importMoldFromGit(
          gitUrl: Uri.file(repoDir.path).toString(),
          tempParent: tempParent,
        );

        expect(
          destination.resolveSymbolicLinksSync(),
          Directory(p.join(destinationParent.path, 'greeter'))
              .resolveSymbolicLinksSync(),
        );
      } finally {
        Directory.current = previousCwd;
      }
    });

    test('falls back to a full shallow clone when sparse clone fails',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(
        repoDir,
        moldName: 'nested',
        subPath: 'molds/api',
        siblingPath: 'other/large.txt',
      );
      final cloneDir = Directory(p.join(workDir.path, 'clone'))..createSync();
      File(p.join(cloneDir.path, 'blocker.txt')).writeAsStringSync('blocked');

      await cloneMoldRepository(
        gitUrl: Uri.file(repoDir.path).toString(),
        destination: cloneDir,
        path: 'molds/api',
      );

      expect(
        File(p.join(cloneDir.path, 'blocker.txt')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(cloneDir.path, 'molds', 'api', 'pubspec.yaml'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(cloneDir.path, 'other', 'large.txt')).existsSync(),
        isTrue,
      );
    });

    test('falls back to a full shallow clone when sparse-checkout set fails',
        () async {
      final repoDir = Directory(p.join(workDir.path, 'repo'))..createSync();
      await _initMoldRepo(
        repoDir,
        moldName: 'nested',
        subPath: 'molds/api',
        siblingPath: 'other/large.txt',
      );
      final cloneDir = Directory(p.join(workDir.path, 'clone'))..createSync();

      await cloneMoldRepository(
        gitUrl: Uri.file(repoDir.path).toString(),
        destination: cloneDir,
        path: 'molds/api',
        gitRunner: (arguments, {workingDirectory}) async {
          if (arguments.isNotEmpty && arguments.first == 'sparse-checkout') {
            return ProcessResult(
              0,
              1,
              '',
              'simulated sparse-checkout failure',
            );
          }
          return Process.run(
            'git',
            arguments,
            workingDirectory: workingDirectory,
          );
        },
      );

      expect(
        File(p.join(cloneDir.path, 'molds', 'api', 'pubspec.yaml'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(cloneDir.path, 'other', 'large.txt')).existsSync(),
        isTrue,
      );
    });
  });

  group('clearMoldImportDirectory', () {
    test('creates a missing directory', () async {
      final missing = Directory(p.join(workDir.path, 'missing_clear'));

      await clearMoldImportDirectory(missing);

      expect(missing.existsSync(), isTrue);
      expect(missing.listSync(), isEmpty);
    });

    test('removes existing directory contents', () async {
      final directory = Directory(p.join(workDir.path, 'clear_me'))
        ..createSync();
      File(p.join(directory.path, 'keep_dir_remove_file.txt'))
          .writeAsStringSync('gone');
      Directory(p.join(directory.path, 'nested')).createSync();

      await clearMoldImportDirectory(directory);

      expect(directory.existsSync(), isTrue);
      expect(directory.listSync(), isEmpty);
    });
  });

  group('describeGitCloneFailure', () {
    test('prefers combined process output', () {
      expect(
        describeGitCloneFailure(
          ProcessResult(0, 1, 'out\n', 'err\n'),
        ),
        'out\nerr',
      );
    });

    test('uses a fallback when output is empty', () {
      expect(
        describeGitCloneFailure(
          ProcessResult(0, 128, '  ', '\n'),
        ),
        'git exited with code 128.',
      );
    });
  });
}
