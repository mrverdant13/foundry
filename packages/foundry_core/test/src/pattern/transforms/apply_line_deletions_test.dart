import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/pattern/transforms/apply_line_deletions.dart';
import 'package:test/test.dart';

void main() {
  group('applyLineDeletions', () {
    const input = '''
This is line 1.
This is line 2.
This is line 3.
This is line 4.
This is line 5.
This is line 6.
This is line 7.
This is line 8.
This is line 9.
This is line 10.
This is line 11.
This is line 12.
This is line 13.
This is line 14.
This is line 15.
This is line 16.
This is line 17.
This is line 18.
This is line 19.
This is line 20.
''';

    const expected = '''
This is line 1.
This is line 7.
This is line 8.
This is line 9.
This is line 10.
This is line 11.
This is line 17.
This is line 18.
This is line 19.
This is line 20.
''';

    final lineDeletions = [
      const PatternLineDeletion(
        filePath: 'file/path',
        ranges: [
          PatternLineRange(start: 1, end: 5),
          PatternLineRange(start: 11, end: 15),
        ],
      ),
      const PatternLineDeletion(
        filePath: 'other/file/path',
        ranges: [
          PatternLineRange(start: 2, end: 6),
          PatternLineRange(start: 12, end: 16),
        ],
      ),
    ];

    test('drops matching ranges for the target file path', () {
      final result = applyLineDeletions(
        content: input,
        relativePosixPath: 'file/path',
        lineDeletions: lineDeletions,
      );

      expect(result, expected);
    });

    test('returns content unchanged when file path does not match', () {
      final result = applyLineDeletions(
        content: input,
        relativePosixPath: 'non-matching/file/path',
        lineDeletions: lineDeletions,
      );

      expect(result, input);
    });

    test('returns content unchanged when no deletions are configured', () {
      final result = applyLineDeletions(
        content: input,
        relativePosixPath: 'file/path',
        lineDeletions: const [],
      );

      expect(result, input);
    });

    test('deletes a single inclusive line (start == end)', () {
      final result = applyLineDeletions(
        content: 'a\nb\nc\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [PatternLineRange(start: 1, end: 1)],
          ),
        ],
      );

      expect(result, 'a\nc\n');
    });

    test('deletes the first and last lines', () {
      final result = applyLineDeletions(
        content: 'a\nb\nc\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [
              PatternLineRange(start: 0, end: 0),
              PatternLineRange(start: 2, end: 2),
            ],
          ),
        ],
      );

      expect(result, 'b\n');
    });

    test('merges overlapping ranges from the same file entry', () {
      final result = applyLineDeletions(
        content: 'a\nb\nc\nd\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [
              PatternLineRange(start: 1, end: 2),
              PatternLineRange(start: 2, end: 3),
            ],
          ),
        ],
      );

      expect(result, 'a\n');
    });

    test('ignores ranges that fall past the end of the file', () {
      final result = applyLineDeletions(
        content: 'a\nb\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [PatternLineRange(start: 10, end: 20)],
          ),
        ],
      );

      expect(result, 'a\nb\n');
    });

    test('treats empty ranges as a no-op for that entry', () {
      final result = applyLineDeletions(
        content: 'a\nb\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [],
          ),
        ],
      );

      expect(result, 'a\nb\n');
    });

    test('matches filePath with POSIX path equality', () {
      final result = applyLineDeletions(
        content: 'keep\ndrop\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: './lib/main.dart',
            ranges: [PatternLineRange(start: 1, end: 1)],
          ),
        ],
      );

      expect(result, 'keep\n');
    });

    test('returns empty string when every line is deleted', () {
      final result = applyLineDeletions(
        content: 'a\nb\nc\n',
        relativePosixPath: 'lib/main.dart',
        lineDeletions: const [
          PatternLineDeletion(
            filePath: 'lib/main.dart',
            ranges: [PatternLineRange(start: 0, end: 2)],
          ),
        ],
      );

      expect(result, isEmpty);
    });
  });
}
