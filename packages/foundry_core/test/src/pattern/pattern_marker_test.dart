import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('parsePatternMarker', () {
    test('parses an empty map', () {
      final marker = parsePatternMarker(
        yamlContent: '{}',
        sourcePath: '/tmp/.foundry/pattern.yaml',
      );

      expect(marker.name, isNull);
      expect(marker.ignore, isEmpty);
    });

    test('parses name and ignore globs', () {
      final marker = parsePatternMarker(
        yamlContent: '''
name: demo_pattern
ignore:
  - .git/**
  - build/**
''',
        sourcePath: '/tmp/.foundry/pattern.yaml',
      );

      expect(marker.name, 'demo_pattern');
      expect(marker.ignore, ['.git/**', 'build/**']);
    });

    test('rejects a non-empty non-string name', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'name: 1',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('rejects ignore values that are not strings', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
ignore:
  - 1
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(isA<PatternMarkerException>()),
      );
    });

    test('rejects invalid YAML', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'name: [unterminated',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(isA<PatternMarkerException>()),
      );
    });
  });
}
