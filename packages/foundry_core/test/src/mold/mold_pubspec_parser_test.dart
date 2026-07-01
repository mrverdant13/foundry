import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pubspec_parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MoldHooks', () {
    test('exposes standard hook paths', () {
      expect(MoldHooks.prepare, 'prepare.dart');
      expect(MoldHooks.shape, 'shape.dart');
      expect(MoldHooks.finish, 'finish.dart');
      expect(MoldHooks.preparePath, p.join('hooks', 'prepare.dart'));
      expect(MoldHooks.shapePath, p.join('hooks', 'shape.dart'));
      expect(MoldHooks.finishPath, p.join('hooks', 'finish.dart'));
      expect(MoldHooks.allPaths, [
        p.join('hooks', 'prepare.dart'),
        p.join('hooks', 'shape.dart'),
        p.join('hooks', 'finish.dart'),
      ]);
    });
  });

  group('parseMoldPubspec', () {
    test('parses required fields', () {
      final pubspec = parseMoldPubspec(
        yamlContent: '''
name: flutter_app
description: Flutter application starter
version: 1.0.0
dependencies:
  foundry_core:
    path: ../foundry_core
''',
        sourcePath: 'pubspec.yaml',
      );

      expect(pubspec.name, 'flutter_app');
      expect(pubspec.description, 'Flutter application starter');
      expect(pubspec.version, '1.0.0');
    });

    test('throws when name is missing', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: '''
description: Missing name
version: 1.0.0
dependencies:
  foundry_core:
    path: ../foundry_core
''',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('throws when description is missing', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: '''
name: demo
version: 1.0.0
dependencies:
  foundry_core:
    path: ../foundry_core
''',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('description'),
          ),
        ),
      );
    });

    test('throws when version is missing', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: '''
name: demo
description: Demo
dependencies:
  foundry_core:
    path: ../foundry_core
''',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('throws when foundry_core dependency is missing', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: '''
name: demo
description: Demo
version: 1.0.0
dependencies: {}
''',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('foundry_core'),
          ),
        ),
      );
    });

    test('throws on invalid yaml', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: 'name: [unclosed',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('throws when pubspec.yaml cannot be parsed', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: 'just a string',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('Could not parse pubspec.yaml'),
          ),
        ),
      );
    });

    test('throws when name is empty', () {
      expect(
        () => parseMoldPubspec(
          yamlContent: '''
name: "   "
description: Demo
version: 1.0.0
dependencies:
  foundry_core:
    path: ../foundry_core
''',
          sourcePath: 'pubspec.yaml',
        ),
        throwsA(isA<MoldLoadException>()),
      );
    });
  });
}
