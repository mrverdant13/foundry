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
      expect(marker.replacements, isEmpty);
      expect(marker.lineDeletions, isEmpty);
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
      expect(marker.replacements, isEmpty);
      expect(marker.lineDeletions, isEmpty);
    });

    test('parses string and regex-object replacements', () {
      final marker = parsePatternMarker(
        yamlContent: r'''
replacements:
  - from: ref_pkg
    to: "{{ package_name }}"
  - from:
      pattern: "Foo(.*)"
      dotAll: true
      multiLine: true
      unicode: true
      caseSensitive: false
    to: "Bar${1}"
''',
        sourcePath: '/tmp/.foundry/pattern.yaml',
      );

      expect(marker.replacements, hasLength(2));
      expect(marker.replacements[0].from.pattern, 'ref_pkg');
      expect(marker.replacements[0].to, '{{ package_name }}');
      expect(marker.replacements[1].from.pattern, 'Foo(.*)');
      expect(marker.replacements[1].from.isDotAll, isTrue);
      expect(marker.replacements[1].from.isMultiLine, isTrue);
      expect(marker.replacements[1].from.isUnicode, isTrue);
      expect(marker.replacements[1].from.isCaseSensitive, isFalse);
      expect(marker.replacements[1].to, r'Bar${1}');
    });

    test('parses lineDeletions with inclusive ranges', () {
      final marker = parsePatternMarker(
        yamlContent: '''
lineDeletions:
  - filePath: lib/main.dart
    ranges:
      - start: 10
        end: 20
      - start: 0
        end: 0
  - filePath: README.md
    ranges: []
''',
        sourcePath: '/tmp/.foundry/pattern.yaml',
      );

      expect(marker.lineDeletions, hasLength(2));
      expect(marker.lineDeletions[0].filePath, 'lib/main.dart');
      expect(marker.lineDeletions[0].ranges, hasLength(2));
      expect(marker.lineDeletions[0].ranges[0].start, 10);
      expect(marker.lineDeletions[0].ranges[0].end, 20);
      expect(marker.lineDeletions[0].ranges[0].contains(10), isTrue);
      expect(marker.lineDeletions[0].ranges[0].contains(20), isTrue);
      expect(marker.lineDeletions[0].ranges[0].contains(21), isFalse);
      expect(marker.lineDeletions[0].ranges[1].start, 0);
      expect(marker.lineDeletions[0].ranges[1].end, 0);
      expect(marker.lineDeletions[1].filePath, 'README.md');
      expect(marker.lineDeletions[1].ranges, isEmpty);
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
      expect(marker.replacements, isEmpty);
      expect(marker.lineDeletions, isEmpty);
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

    test('rejects replacements when it is not a list', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'replacements: {}',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements'),
          ),
        ),
      );
    });

    test('rejects a replacement entry that is not a map', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - ref_pkg
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements[0]'),
          ),
        ),
      );
    });

    test('rejects a replacement with a non-string to', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - from: ref_pkg
    to: 1
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements[0].to'),
          ),
        ),
      );
    });

    test('rejects a replacement with an empty from string', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - from: ""
    to: other
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements[0].from'),
          ),
        ),
      );
    });

    test('rejects a regex object without a pattern', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - from:
      dotAll: true
    to: other
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements[0].from.pattern'),
          ),
        ),
      );
    });

    test('rejects a non-boolean regex flag', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - from:
      pattern: Foo
      dotAll: "true"
    to: Bar
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('replacements[0].from.dotAll'),
          ),
        ),
      );
    });

    test('rejects an invalid regular expression pattern', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
replacements:
  - from: "("
    to: other
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('regular expression'),
          ),
        ),
      );
    });

    test('rejects lineDeletions when it is not a list', () {
      expect(
        () => parsePatternMarker(
          yamlContent: 'lineDeletions: lib/main.dart',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('lineDeletions'),
          ),
        ),
      );
    });

    test('rejects a lineDeletion without filePath', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
lineDeletions:
  - ranges:
      - start: 0
        end: 1
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('lineDeletions[0].filePath'),
          ),
        ),
      );
    });

    test('rejects a lineDeletion without ranges', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
lineDeletions:
  - filePath: lib/main.dart
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('lineDeletions[0].ranges'),
          ),
        ),
      );
    });

    test('rejects a line range with start greater than end', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
lineDeletions:
  - filePath: lib/main.dart
    ranges:
      - start: 5
        end: 2
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('start <= end'),
          ),
        ),
      );
    });

    test('rejects a negative line range bound', () {
      expect(
        () => parsePatternMarker(
          yamlContent: '''
lineDeletions:
  - filePath: lib/main.dart
    ranges:
      - start: -1
        end: 2
''',
          sourcePath: '/tmp/.foundry/pattern.yaml',
        ),
        throwsA(
          isA<PatternMarkerException>().having(
            (error) => error.issues.single.message,
            'message',
            contains('non-negative'),
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
