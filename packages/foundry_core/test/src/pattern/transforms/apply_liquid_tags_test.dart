import 'package:foundry_core/src/pattern/transforms/apply_liquid_tags.dart';
import 'package:test/test.dart';

void main() {
  group('applyLiquidTags', () {
    test('unwraps output and tag Liquid from all comment flavors with x flags',
        () {
      const input = '''
text
/*x{{some-key}}*/
more text
#{% if other-key %}x#
yet more text
and even
<!--x{{yet-another-key}}x-->
more text
''';
      const expected = '''
text{{some-key}}
more text
{% if other-key %}yet more text
and even{{yet-another-key}}more text
''';

      final result = applyLiquidTags(content: input);

      expect(result, expected);
    });

    test('retains adjacent whitespace when x flags are absent', () {
      const input = '''
before /*{{name}}*/ after
before #{% if ready %}# after
before <!--{{name}}--> after
''';
      const expected = '''
before {{name}} after
before {% if ready %} after
before {{name}} after
''';

      final result = applyLiquidTags(content: input);

      expect(result, expected);
    });

    test('drops only leading whitespace with dropLeading x flag', () {
      const input = 'line /*x{{tag}}*/ rest';

      final result = applyLiquidTags(content: input);

      expect(result, 'line{{tag}} rest');
    });

    test('drops only trailing whitespace with dropTrailing x flag', () {
      const input = 'line #{% if tag %}x# rest';

      final result = applyLiquidTags(content: input);

      expect(result, 'line {% if tag %}rest');
    });

    test('unwraps multiple tags in the same content', () {
      const input = '''
/*{{a}}*/
middle
#{% if b %}#
''';
      const expected = '''
{{a}}
middle
{% if b %}
''';

      final result = applyLiquidTags(content: input);

      expect(result, expected);
    });

    test('unwraps both tag kinds for each comment flavor', () {
      for (final case_ in [
        (
          output: '/*{{name}}*/',
          tag: '/*{% if x %}*/',
        ),
        (
          output: '#{{name}}#',
          tag: '#{% if x %}#',
        ),
        (
          output: '<!--{{name}}-->',
          tag: '<!--{% if x %}-->',
        ),
      ]) {
        expect(
          applyLiquidTags(content: 'A${case_.output}B${case_.tag}C'),
          'A{{name}}B{% if x %}C',
        );
      }
    });

    test('leaves content without liquid comment wrappers unchanged', () {
      const input = '''
plain text
/* not a liquid comment */
# also not #
<!-- {{unclosed
{{already_live}}
{% if live %}
''';

      final result = applyLiquidTags(content: input);

      expect(result, input);
    });
  });

  group('parkLiquidTagAnnotations / restoreParkedLiquidTags', () {
    test('parks annotations so braces are absent until restore', () {
      const input = 'before /*{{name}}*/ after #{% if x %}# end';

      final parked = parkLiquidTagAnnotations(input);

      expect(parked.content.contains('{{'), isFalse);
      expect(parked.content.contains('{%'), isFalse);
      expect(parked.replacements, [' {{name}} ', ' {% if x %} ']);

      final restored = restoreParkedLiquidTags(
        parked.content,
        replacements: parked.replacements,
      );
      expect(restored, 'before {{name}} after {% if x %} end');
    });

    test('preserves x-flag whitespace decisions across park/restore', () {
      const input = 'a /*x{{name}}x*/ b';

      final parked = parkLiquidTagAnnotations(input);
      final restored = restoreParkedLiquidTags(
        parked.content,
        replacements: parked.replacements,
      );

      expect(restored, 'a{{name}}b');
    });

    test('restore is a no-op when no replacements were parked', () {
      expect(
        restoreParkedLiquidTags('plain', replacements: const []),
        'plain',
      );
    });
  });
}
