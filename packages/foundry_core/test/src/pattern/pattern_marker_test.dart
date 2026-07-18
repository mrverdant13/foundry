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

    test('parses a null YAML document as an empty marker', () {
      final marker = parsePatternMarker(
        yamlContent: '',
        sourcePath: '/tmp/.foundry/pattern.yaml',
      );

      expect(marker.name, isNull);
      expect(marker.ignore, isEmpty);
    });

    test('rejects an empty name', () {
      expect(
        () => parsePatternMarker(
          yamlContent: "name: '   '",
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

    test('rejects ignore when it is not a list', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'ignore: build/**',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('ignore'),
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

    test('rejects empty ignore entries', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
ignore:
  - '   '
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('non-empty'),
          ),
        ),
      );
    });

    test('rejects invalid YAML', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'name: [unterminated',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.toString(),
            'toString',
            contains('Failed to parse pattern marker'),
          ),
        ),
      );
    });

    test('rejects a non-map YAML document', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '[]',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('Not a map'),
          ),
        ),
      );
    });
  });
}
