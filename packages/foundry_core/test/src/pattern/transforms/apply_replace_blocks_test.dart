import 'package:foundry_core/src/pattern/transforms/apply_replace_blocks.dart';
import 'package:test/test.dart';

void main() {
  group('applyReplaceBlocks', () {
    test('replaces scaffold with indented replacement lines', () {
      const input = '''
line0
line/*replace-start*/
asdf
asdf asdf
/*with i0*/
// 1
// line2
/*replace-end*/
line3
#replace-start#
asdf
asdf asdf
#with i1#
# line4
# line5
#replace-end#
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

      final result = applyReplaceBlocks(content: input);

      expect(result, expected);
    });

    test('resolves HTML comment replace blocks', () {
      const input = '''
before
<!--replace-start-->
ignored
<!--with i2-->
<!-- line a-->
<!-- line b-->
<!--replace-end-->
after
''';
      const expected = '''
before
  line a
  line b
after
''';

      final result = applyReplaceBlocks(content: input);

      expect(result, expected);
    });

    group('replace blocks by comment flavor', () {
      for (final case_ in [
        (
          start: '/*replace-start*/',
          withMarker: '/*with*/',
          end: '/*replace-end*/',
          line: '// value',
        ),
        (
          start: '#replace-start#',
          withMarker: '#with#',
          end: '#replace-end#',
          line: '# value',
        ),
        (
          start: '<!--replace-start-->',
          withMarker: '<!--with-->',
          end: '<!--replace-end-->',
          line: '<!-- value-->',
        ),
      ]) {
        test(
          'emits replacement for ${case_.start} … ${case_.end}',
          () {
            final input = '''
keep-before
${case_.start}
scaffold
${case_.withMarker}
${case_.line}
${case_.end}
keep-after
''';
            const expected = '''
keep-before
value
keep-after
''';

            final result = applyReplaceBlocks(content: input);

            expect(result, expected);
            expect(result, isNot(contains('replace-start')));
            expect(result, isNot(contains('scaffold')));
          },
        );
      }
    });

    test('throws FormatException when with section line is invalid', () {
      const input = '''
line/*replace-start*/
old
/*with i0*/
// valid
not a comment
/*replace-end*/
''';

      expect(
        () => applyReplaceBlocks(content: input),
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

    test('returns content unchanged when no replace blocks are present', () {
      const input = '''
line 0
line 1
line 2
''';

      final result = applyReplaceBlocks(content: input);

      expect(result, input);
    });

    test('resolves replace blocks in CRLF content', () {
      const input = 'line0\r\n'
          'line/*replace-start*/\r\n'
          'ignored\r\n'
          '/*with i0*/\r\n'
          '// 1\r\n'
          '// line2\r\n'
          '/*replace-end*/\r\n'
          'line3\r\n';
      const expected = 'line0\r\n'
          'line1\n'
          'line2\r\n'
          'line3\r\n';

      final result = applyReplaceBlocks(content: input);

      expect(result, expected);
    });
  });
}
