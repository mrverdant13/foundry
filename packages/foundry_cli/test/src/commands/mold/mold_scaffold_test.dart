import 'dart:io';

import 'package:foundry_cli/src/commands/mold/mold_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_scaffold_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('isValidMoldName', () {
    test('accepts lowercase letters, digits, and underscores', () {
      expect(isValidMoldName('flutter_app'), isTrue);
      expect(isValidMoldName('app2'), isTrue);
      expect(isValidMoldName('_private'), isTrue);
    });

    test('rejects names starting with a digit', () {
      expect(isValidMoldName('2fast'), isFalse);
    });

    test('rejects names with invalid characters', () {
      expect(isValidMoldName('flutter-app'), isFalse);
      expect(isValidMoldName('Flutter'), isFalse);
      expect(isValidMoldName(''), isFalse);
    });
  });

  group('defaultMoldName', () {
    test('lowercases the directory basename', () {
      final dir = Directory(p.join(workDir.path, 'FlutterApp'));
      expect(defaultMoldName(dir), 'flutterapp');
    });

    test('replaces invalid characters with underscores', () {
      final dir = Directory(p.join(workDir.path, 'my-flutter-app'));
      expect(defaultMoldName(dir), 'my_flutter_app');
    });

    test('prefixes names that would start with a digit', () {
      final dir = Directory(p.join(workDir.path, '2024_app'));
      expect(defaultMoldName(dir), 'mold_2024_app');
    });
  });

  group('MoldScaffoldException', () {
    test('toString returns the message', () {
      const exception = MoldScaffoldException('boom');

      expect(exception.toString(), 'boom');
    });
  });

  group('scaffoldMold', () {
    test('creates pubspec.yaml, variables.dart, template/, and hooks/',
        () async {
      await scaffoldMold(directory: workDir, name: 'flutter_app');

      final pubspec = File(p.join(workDir.path, 'pubspec.yaml'));
      expect(pubspec.existsSync(), isTrue);
      expect(pubspec.readAsStringSync(), contains('name: flutter_app'));
      expect(
        pubspec.readAsStringSync(),
        contains('foundry_core: $scaffoldFoundryCoreConstraint'),
      );

      final variables = File(p.join(workDir.path, 'variables.dart'));
      expect(variables.existsSync(), isTrue);
      expect(variables.readAsStringSync(), contains('moldVariables'));
      expect(variables.readAsStringSync(), contains('FoundryStringVariable'));

      expect(Directory(p.join(workDir.path, 'template')).existsSync(), isTrue);
      expect(Directory(p.join(workDir.path, 'hooks')).existsSync(), isTrue);
    });

    test('creates the target directory when it does not exist yet', () async {
      final target = Directory(p.join(workDir.path, 'nested', 'mold_dir'));

      await scaffoldMold(directory: target, name: 'nested_mold');

      expect(File(p.join(target.path, 'pubspec.yaml')).existsSync(), isTrue);
    });

    test('fails when a pubspec.yaml already exists', () async {
      File(p.join(workDir.path, 'pubspec.yaml')).createSync();

      await expectLater(
        scaffoldMold(directory: workDir, name: 'flutter_app'),
        throwsA(
          isA<MoldScaffoldException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });
  });
}
