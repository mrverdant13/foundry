import 'package:foundry_core/src/pattern/transforms/apply_spacing_groups.dart';
import 'package:test/test.dart';

void main() {
  group('applySpacingGroups', () {
    test('resolves spacing groups in all comment flavors', () {
      const input = '''
text
/*w 2v 4> w*/
more te#ww#xt
#w 4v 2> w#
yet more <!--w 5> w--> text
''';
      const expected = '''
text

    more text



  yet more     text
''';

      final result = applySpacingGroups(content: input);

      expect(result, expected);
    });

    test('resolves empty spacing groups and consumes adjacent whitespace', () {
      const input = '''
before /*w w*/ after
before #w w# after
before <!--w w--> after
''';
      const expected = '''
beforeafter
beforeafter
beforeafter
''';

      final result = applySpacingGroups(content: input);

      expect(result, expected);
    });

    test('expands newline actions', () {
      const input = 'line/*w 3v w*/end';

      final result = applySpacingGroups(content: input);

      expect(result, 'line\n\n\nend');
    });

    test('expands space actions', () {
      const input = 'line#w 3> w#end';

      final result = applySpacingGroups(content: input);

      expect(result, 'line   end');
    });

    test('expands mixed Nv and N> actions in order', () {
      const input = 'a/*w 1v 2> 1v 3> w*/b';

      final result = applySpacingGroups(content: input);

      expect(result, 'a\n  \n   b');
    });

    test('leaves content without spacing groups unchanged', () {
      const input = '''
plain text
/*not a spacing group*/
#w missing closing marker
<!--w 2v-->
''';

      final result = applySpacingGroups(content: input);

      expect(result, input);
    });
  });
}
