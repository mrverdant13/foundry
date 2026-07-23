import 'package:foundry_core/src/pattern/transforms/apply_insert_blocks.dart';
import 'package:test/test.dart';

void main() {
  group('applyInsertBlocks', () {
    test('inlines insert blocks from C-style and hash comments', () {
      const input = '''
line0
line/*insert-start*/
// 1
// line2
/*insert-end*/
line3
#insert-start#
# line4
# line5
#insert-end#
line6
''';
      const expected = '''
line0
line1
line2
line3
line4
line5
line6
''';

      final result = applyInsertBlocks(content: input);

      expect(result, expected);
    });

    test('trims leading and trailing whitespace from comment lines', () {
      const input = '''
line/*insert-start*/
              // const foo
// bar
              // baz
/*insert-end*/
#insert-start#
    # line4
# line5
#insert-end#
<!--insert-start-->
    <!-- line a-->
<!-- line b-->
<!--insert-end-->
''';
      const expected = '''
lineconst foo
bar
baz
line4
line5
line a
line b
''';

      final result = applyInsertBlocks(content: input);

      expect(result, expected);
    });

    test('resolves HTML comment insert blocks', () {
      const input = '''
before
<!--insert-start-->
<!-- line a-->
<!-- line b-->
<!--insert-end-->
after
''';
      const expected = '''
before
line a
line b
after
''';

      final result = applyInsertBlocks(content: input);

      expect(result, expected);
    });

    group('insert blocks by comment flavor', () {
      for (final case_ in [
        (
          start: '/*insert-start*/',
          end: '/*insert-end*/',
          line: '// value',
        ),
        (
          start: '#insert-start#',
          end: '#insert-end#',
          line: '# value',
        ),
        (
          start: '<!--insert-start-->',
          end: '<!--insert-end-->',
          line: '<!-- value-->',
        ),
      ]) {
        test(
          'emits insertion for ${case_.start} … ${case_.end}',
          () {
            final input = '''
keep-before
${case_.start}
${case_.line}
${case_.end}
keep-after
''';
            const expected = '''
keep-before
value
keep-after
''';

            final result = applyInsertBlocks(content: input);

            expect(result, expected);
            expect(result, isNot(contains('insert-start')));
            expect(result, isNot(contains('insert-end')));
          },
        );
      }
    });

    group('empty insert bodies by comment flavor', () {
      for (final case_ in [
        (
          start: '/*insert-start*/',
          end: '/*insert-end*/',
        ),
        (
          start: '#insert-start#',
          end: '#insert-end#',
        ),
        (
          start: '<!--insert-start-->',
          end: '<!--insert-end-->',
        ),
      ]) {
        test(
          'removes markers for empty ${case_.start} … ${case_.end}',
          () {
            final input = '''
keep-before
${case_.start}
${case_.end}
keep-after
''';
            const expected = '''
keep-before

keep-after
''';

            final result = applyInsertBlocks(content: input);

            expect(result, expected);
            expect(result, isNot(contains('insert-start')));
            expect(result, isNot(contains('insert-end')));
          },
        );
      }
    });

    test('throws FormatException when insert section line is invalid', () {
      const input = '''
line/*insert-start*/
// valid
not a comment
/*insert-end*/
''';

      expect(
        () => applyInsertBlocks(content: input),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('C-style comment'),
              contains('not a comment'),
            ),
          ),
        ),
      );
    });

    test('throws FormatException when C-style line is not comment-prefixed',
        () {
      const input = '''
line/*insert-start*/
code // not comment-prefixed
/*insert-end*/
''';

      expect(
        () => applyInsertBlocks(content: input),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('C-style comment'),
              contains('code // not comment-prefixed'),
            ),
          ),
        ),
      );
    });

    test('throws FormatException when hash line is not comment-prefixed', () {
      const input = '''
#insert-start#
code # not comment-prefixed
#insert-end#
''';

      expect(
        () => applyInsertBlocks(content: input),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('hash comment'),
              contains('code # not comment-prefixed'),
            ),
          ),
        ),
      );
    });

    test('throws FormatException when HTML line is not comment-prefixed', () {
      const input = '''
<!--insert-start-->
code <!-- not comment-prefixed-->
<!--insert-end-->
''';

      expect(
        () => applyInsertBlocks(content: input),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('HTML comment'),
              contains('code <!-- not comment-prefixed-->'),
            ),
          ),
        ),
      );
    });

    test('returns content unchanged when no insert blocks are present', () {
      const input = '''
line 0
line 1
line 2
''';

      final result = applyInsertBlocks(content: input);

      expect(result, input);
    });

    test('resolves insert blocks in CRLF content', () {
      const input = 'line0\r\n'
          'line/*insert-start*/\r\n'
          '// 1\r\n'
          '// line2\r\n'
          '/*insert-end*/\r\n'
          'line3\r\n';
      const expected = 'line0\r\n'
          'line1\n'
          'line2\r\n'
          'line3\r\n';

      final result = applyInsertBlocks(content: input);

      expect(result, expected);
    });
  });
}
