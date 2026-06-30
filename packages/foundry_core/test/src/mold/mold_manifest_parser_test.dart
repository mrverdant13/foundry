import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_manifest_parser.dart';
import 'package:test/test.dart';

void main() {
  group('MoldHooks', () {
    test('exposes standard hook paths', () {
      expect(MoldHooks.prepare, 'prepare.dart');
      expect(MoldHooks.shape, 'shape.dart');
      expect(MoldHooks.finish, 'finish.dart');
      expect(MoldHooks.preparePath, 'hooks/prepare.dart');
      expect(MoldHooks.shapePath, 'hooks/shape.dart');
      expect(MoldHooks.finishPath, 'hooks/finish.dart');
      expect(MoldHooks.allPaths, [
        'hooks/prepare.dart',
        'hooks/shape.dart',
        'hooks/finish.dart',
      ]);
    });
  });

  group('parseMoldManifest', () {
    test('parses required fields', () {
      final manifest = parseMoldManifest(
        yamlContent: '''
name: flutter_app
description: Flutter application starter
''',
        sourcePath: 'mold.yaml',
      );

      expect(manifest.name, 'flutter_app');
      expect(manifest.description, 'Flutter application starter');
    });

    test('ignores legacy hooks declarations in mold.yaml', () {
      final manifest = parseMoldManifest(
        yamlContent: '''
name: demo
description: Demo mold
hooks:
  prepare: custom/prepare.dart
  shape: custom/shape.dart
  finish: custom/finish.dart
''',
        sourcePath: 'mold.yaml',
      );

      expect(manifest.name, 'demo');
      expect(manifest.description, 'Demo mold');
    });

    test('throws when name is missing', () {
      expect(
        () => parseMoldManifest(
          yamlContent: 'description: Missing name',
          sourcePath: 'mold.yaml',
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
        () => parseMoldManifest(
          yamlContent: 'name: demo',
          sourcePath: 'mold.yaml',
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

    test('throws on invalid yaml', () {
      expect(
        () => parseMoldManifest(
          yamlContent: 'name: [unclosed',
          sourcePath: 'mold.yaml',
        ),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('throws when document root is not a map', () {
      expect(
        () => parseMoldManifest(
          yamlContent: 'just a string',
          sourcePath: 'mold.yaml',
        ),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('YAML map'),
          ),
        ),
      );
    });

    test('throws when name is empty', () {
      expect(
        () => parseMoldManifest(
          yamlContent: '''
name: "   "
description: Demo
''',
          sourcePath: 'mold.yaml',
        ),
        throwsA(isA<MoldLoadException>()),
      );
    });
  });
}
