import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_import_support.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_import_support_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('readMoldNameForImport', () {
    test('returns the pubspec name field', () {
      final pubspecFile = File(p.join(workDir.path, 'pubspec.yaml'))
        ..writeAsStringSync('''
name: greeter
description: A test fixture
version: 0.0.1
''');

      expect(readMoldNameForImport(pubspecFile), 'greeter');
    });

    test('throws when the pubspec file does not exist', () {
      final pubspecFile =
          File(p.join(workDir.path, 'does_not_exist', 'pubspec.yaml'));

      expect(
        () => readMoldNameForImport(pubspecFile),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('Missing required file "pubspec.yaml"'),
          ),
        ),
      );
    });

    test('throws when the pubspec is missing the name field', () {
      final pubspecFile = File(p.join(workDir.path, 'pubspec.yaml'))
        ..writeAsStringSync('description: No name here\n');

      expect(
        () => readMoldNameForImport(pubspecFile),
        throwsA(
          isA<MoldImportException>().having(
            (error) => error.message,
            'message',
            contains('Could not read mold name'),
          ),
        ),
      );
    });
  });
}
