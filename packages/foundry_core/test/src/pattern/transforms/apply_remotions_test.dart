import 'package:foundry_core/src/pattern/transforms/apply_remotions.dart';
import 'package:test/test.dart';

void main() {
  group('applyRemotions', () {
    test('removes remove blocks with whitespace control flags', () {
      const input = '''
line   <!--x-remove-start--> asdf
asdf asdf
asdf <!--remove-end-x-->    0
line 1
line  /*x-remove-start*/ asdf
asdf asdf
asdf /*remove-end*/  2
line   #remove-start# asdf
asdf asdf
asdf #remove-end-x#       3
line  <!--remove-start--> asdf
asdf asdf
asdf <!--remove-end-->  4
line 5
''';
      const expected = '''
line0
line 1
line  2
line   3
line    4
line 5
''';

      final result = applyRemotions(content: input);

      expect(result, expected);
    });

    group('drop markers', () {
      const suffix = '''
line 3
line 4
line 5
''';

      for (final dropCase in ['/*drop*/', '#drop#', '<!--drop-->']) {
        test('removes content from $dropCase to end of file', () {
          final input = '''
line 0
line 1
line 2
$dropCase
$suffix''';

          const expected = '''
line 0
line 1
line 2
''';

          final result = applyRemotions(content: input);

          expect(result, expected);
        });
      }
    });

    group('remove blocks by comment flavor', () {
      for (final markers in [
        ('/*x-remove-start*/', '/*remove-end-x*/'),
        ('#x-remove-start#', '#remove-end-x#'),
        ('<!--x-remove-start-->', '<!--remove-end-x-->'),
      ]) {
        test(
          'removes paired block for ${markers.$1} … ${markers.$2}',
          () {
            final input =
                'keep-before ${markers.$1} gone ${markers.$2} keep-after';
            const expected = 'keep-beforekeep-after';

            final result = applyRemotions(content: input);

            expect(result, expected);
          },
        );
      }
    });

    group('drop nested inside remove blocks', () {
      for (final case_ in [
        (
          start: '/*x-remove-start*/',
          drop: '/*drop*/',
          end: '/*remove-end-x*/',
        ),
        (
          start: '#x-remove-start#',
          drop: '#drop#',
          end: '#remove-end-x#',
        ),
        (
          start: '<!--x-remove-start-->',
          drop: '<!--drop-->',
          end: '<!--remove-end-x-->',
        ),
      ]) {
        test(
          'keeps content after remove block when ${case_.drop} is nested',
          () {
            final input = '''
keep-before
${case_.start}
scaffold
${case_.drop}
more
${case_.end}
keep-after
''';
            const expected = 'keep-beforekeep-after\n';

            final result = applyRemotions(content: input);

            expect(result, expected);
            expect(result, isNot(contains('remove-start')));
            expect(result, isNot(contains('drop')));
          },
        );
      }
    });

    test('returns content unchanged when no remotion markers are present', () {
      const input = '''
line 0
line 1
line 2
''';

      final result = applyRemotions(content: input);

      expect(result, input);
    });
  });
}
