import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_manifest_parser.dart';
import 'package:test/test.dart';

void main() {
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
      expect(manifest.hooks.isEmpty, isTrue);
    });

    test('parses optional hook paths', () {
      final manifest = parseMoldManifest(
        yamlContent: '''
name: demo
description: Demo mold
hooks:
  prepare: hooks/prepare.dart
  shape: hooks/shape.dart
  finish: hooks/finish.dart
''',
        sourcePath: 'mold.yaml',
      );

      expect(manifest.hooks.prepare, 'hooks/prepare.dart');
      expect(manifest.hooks.shape, 'hooks/shape.dart');
      expect(manifest.hooks.finish, 'hooks/finish.dart');
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
  });
}
