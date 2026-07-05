import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _fixtureRoot() {
  var current = Directory.current;
  while (true) {
    final fixture =
        Directory(p.join(current.path, 'test', 'fixtures', 'importable_mold'));
    if (fixture.existsSync()) {
      return Directory(p.join(current.path, 'test', 'fixtures'));
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      fail('Could not locate test/fixtures from ${Directory.current.path}');
    }
    current = parent;
  }
}

void main() {
  late Directory fixtures;
  late Directory workDir;

  setUp(() {
    fixtures = _fixtureRoot();
    workDir = Directory.systemTemp.createTempSync('foundry_local_import_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('importMoldFromLocal', () {
    test('copies the fixture mold to a directory named after pubspec name',
        () async {
      final destination = await importMoldFromLocal(
        sourcePath: p.join(fixtures.path, 'importable_mold'),
        destinationParent: workDir,
      );

      expect(destination.path, p.join(workDir.path, 'greeter'));
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(destination.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
    });

    test('fails when the source directory does not exist', () async {
      await expectLater(
        importMoldFromLocal(
          sourcePath: p.join(workDir.path, 'does_not_exist'),
          destinationParent: workDir,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('fails when the source directory is missing pubspec.yaml', () async {
      final emptySource = Directory(p.join(workDir.path, 'empty_source'))
        ..createSync();

      await expectLater(
        importMoldFromLocal(
          sourcePath: emptySource.path,
          destinationParent: workDir,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
      );
    });

    test('fails when destination exists and force is false', () async {
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();
      Directory(p.join(destinationParent.path, 'greeter')).createSync();

      await expectLater(
        importMoldFromLocal(
          sourcePath: p.join(fixtures.path, 'importable_mold'),
          destinationParent: destinationParent,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('overwrites an existing destination when force is true', () async {
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();
      final existing = Directory(p.join(destinationParent.path, 'greeter'))
        ..createSync();
      File(p.join(existing.path, 'stale.txt')).writeAsStringSync('stale');

      final destination = await importMoldFromLocal(
        sourcePath: p.join(fixtures.path, 'importable_mold'),
        destinationParent: destinationParent,
        force: true,
      );

      expect(File(p.join(destination.path, 'stale.txt')).existsSync(), isFalse);
      expect(
        File(p.join(destination.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('fails when the mold name would escape the destination parent',
        () async {
      final source = Directory(p.join(workDir.path, 'source'))..createSync();
      File(p.join(source.path, 'pubspec.yaml')).writeAsStringSync('''
name: ../escaped
description: A mold name attempting a path traversal
version: 0.0.1
''');
      final destinationParent = Directory(p.join(workDir.path, 'dest'))
        ..createSync();

      await expectLater(
        importMoldFromLocal(
          sourcePath: source.path,
          destinationParent: destinationParent,
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

    test('fails when the destination would be inside the source', () async {
      final source = Directory(p.join(workDir.path, 'greeter'))..createSync();
      File(p.join(source.path, 'pubspec.yaml')).writeAsStringSync('''
name: greeter
description: Self-nesting fixture
version: 0.0.1
''');

      await expectLater(
        importMoldFromLocal(
          sourcePath: source.path,
          destinationParent: workDir,
        ),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('cannot be inside the source'),
          ),
        ),
      );
    });
  });
}
