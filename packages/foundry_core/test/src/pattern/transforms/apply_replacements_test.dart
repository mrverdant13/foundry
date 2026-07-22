import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replacements.dart';
import 'package:test/test.dart';

void main() {
  group('applyReplacement', () {
    test('replaces a simple pattern with a literal string', () {
      expect(
        applyReplacement(
          input: 'use ref_pkg here',
          replacement: PatternReplacement(
            from: RegExp('ref_pkg'),
            to: 'my_pkg',
          ),
        ),
        'use my_pkg here',
      );
    });

    test(r'interpolates ${n} capture groups', () {
      expect(
        applyReplacement(
          input: 'FooBarBaz',
          replacement: PatternReplacement(
            from: RegExp(r'Foo(.*)Baz'),
            to: r'Bar${1}',
          ),
        ),
        'BarBar',
      );
    });

    test('interpolates multiple distinct capture groups', () {
      expect(
        applyReplacement(
          input: 'a-b-c',
          replacement: PatternReplacement(
            from: RegExp(r'(a)-(b)-(c)'),
            to: r'${3}/${2}/${1}',
          ),
        ),
        'c/b/a',
      );
    });

    test('missing capture groups resolve to empty strings', () {
      expect(
        applyReplacement(
          input: 'only-one',
          replacement: PatternReplacement(
            from: RegExp(r'(only)-one'),
            to: r'${1}${2}',
          ),
        ),
        'only',
      );
    });

    test('replaces every non-overlapping match', () {
      expect(
        applyReplacement(
          input: 'aa-aa',
          replacement: PatternReplacement(
            from: RegExp('aa'),
            to: 'bb',
          ),
        ),
        'bb-bb',
      );
    });
  });

  group('applyReplacements', () {
    test('returns input unchanged when the list is empty', () {
      expect(
        applyReplacements(input: 'unchanged', replacements: const []),
        'unchanged',
      );
    });

    test('applies replacements sequentially', () {
      expect(
        applyReplacements(
          input: 'ref_pkg/foo.dart',
          replacements: [
            PatternReplacement(from: RegExp('ref_pkg'), to: 'acme'),
            PatternReplacement(from: RegExp('foo'), to: 'bar'),
          ],
        ),
        'acme/bar.dart',
      );
    });

    test('later replacements see earlier outputs', () {
      expect(
        applyReplacements(
          input: 'alpha',
          replacements: [
            PatternReplacement(from: RegExp('alpha'), to: 'beta'),
            PatternReplacement(from: RegExp('beta'), to: 'gamma'),
          ],
        ),
        'gamma',
      );
    });
  });
}
