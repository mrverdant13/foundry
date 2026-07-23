import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_pattern_content.dart';
import 'package:test/test.dart';

void main() {
  group('resolvePatternContent', () {
    test('leaves plain text unchanged', () {
      expect(resolvePatternContent('Hello world'), 'Hello world');
    });

    test('liquidizes content that contains mustache-style braces', () {
      expect(
        resolvePatternContent('Hello {{ name }}'),
        'Hello {{ "{{" }} name }}',
      );
    });

    test('liquidizes content that contains Liquid tags', () {
      expect(
        resolvePatternContent('{% if true %}yes{% endif %}'),
        '{{ "{%" }} if true %}yes{{ "{%" }} endif %}',
      );
    });

    test('applies line deletions before liquidize', () {
      expect(
        resolvePatternContent(
          'keep\n{{ drop_me }}\nstay\n',
          relativePosixPath: 'README.md',
          lineDeletions: const [
            PatternLineDeletion(
              filePath: 'README.md',
              ranges: [PatternLineRange(start: 1, end: 1)],
            ),
          ],
        ),
        'keep\nstay\n',
      );
    });

    test('liquidizes remaining braces after deletions', () {
      expect(
        resolvePatternContent(
          'drop\nHello {{ name }}\n',
          relativePosixPath: 'README.md',
          lineDeletions: const [
            PatternLineDeletion(
              filePath: 'README.md',
              ranges: [PatternLineRange(start: 0, end: 0)],
            ),
          ],
        ),
        'Hello {{ "{{" }} name }}\n',
      );
    });

    test('ignores deletions for a non-matching path', () {
      expect(
        resolvePatternContent(
          'a\nb\n',
          relativePosixPath: 'lib/kept.dart',
          lineDeletions: const [
            PatternLineDeletion(
              filePath: 'lib/other.dart',
              ranges: [PatternLineRange(start: 0, end: 1)],
            ),
          ],
        ),
        'a\nb\n',
      );
    });

    test('applies content replacements after liquidize', () {
      expect(
        resolvePatternContent(
          'use ref_pkg',
          replacements: [
            PatternReplacement(
              from: RegExp('ref_pkg'),
              to: '{{ package_name }}',
            ),
          ],
        ),
        'use {{ package_name }}',
      );
    });

    test('keeps injected Liquid live while escaping source braces', () {
      expect(
        resolvePatternContent(
          'Hello {{ literal }} and ref_pkg',
          replacements: [
            PatternReplacement(
              from: RegExp('ref_pkg'),
              to: '{{ package_name }}',
            ),
          ],
        ),
        'Hello {{ "{{" }} literal }} and {{ package_name }}',
      );
    });

    test('applies replacements with capture interpolation', () {
      expect(
        resolvePatternContent(
          'FooWidget',
          replacements: [
            PatternReplacement(
              from: RegExp('Foo(.*)'),
              to: r'Bar${1}',
            ),
          ],
        ),
        'BarWidget',
      );
    });

    test('applies remotions after replacements', () {
      expect(
        resolvePatternContent(
          'keep ref_pkg /*x-remove-start*/ gone /*remove-end-x*/end',
          replacements: [
            PatternReplacement(
              from: RegExp('ref_pkg'),
              to: '{{ package_name }}',
            ),
          ],
        ),
        'keep {{ package_name }}end',
      );
    });

    test('applies drop remotion through end of file', () {
      expect(
        resolvePatternContent('keep\n/*drop*/\ngone\n'),
        'keep\n',
      );
    });

    test('applies replace blocks after remotions', () {
      expect(
        resolvePatternContent(
          'keep\n'
          '/*remove-start*/\n'
          'gone\n'
          '/*remove-end*/\n'
          '/*replace-start*/\n'
          'scaffold\n'
          '/*with*/\n'
          '// value\n'
          '/*replace-end*/\n'
          'end\n',
        ),
        'keep\n\nvalue\nend\n',
      );
    });

    test('applies insert blocks after replace blocks', () {
      expect(
        resolvePatternContent(
          'keep\n'
          '/*replace-start*/\n'
          'scaffold\n'
          '/*with*/\n'
          '// replaced\n'
          '/*replace-end*/\n'
          'mid/*insert-start*/\n'
          '// inserted\n'
          '/*insert-end*/\n'
          'end\n',
        ),
        'keep\nreplaced\nmidinserted\nend\n',
      );
    });

    test('unwraps liquid tags after insert blocks as live Liquid', () {
      expect(
        resolvePatternContent(
          'keep\n'
          'mid/*insert-start*/\n'
          '// /*{{nested}}*/\n'
          '/*insert-end*/\n'
          '/*{{name}}*/\n'
          '#{% if ready %}#\n'
          'end\n',
        ),
        'keep\nmid{{nested}}\n{{name}}\n{% if ready %}\nend\n',
      );
    });

    test('keeps accidental braces escaped while liquid tags stay live', () {
      expect(
        resolvePatternContent(
          'Hello {{ literal }} and /*{{name}}*/',
        ),
        'Hello {{ "{{" }} literal }} and {{name}}',
      );
    });

    test('honors liquid tag x flags through the full pipeline', () {
      expect(
        resolvePatternContent('before /*x{{name}}x*/ after'),
        'before{{name}}after',
      );
    });

    test('unwraps liquid tags introduced by replacements', () {
      expect(
        resolvePatternContent(
          'use PLACEHOLDER here',
          replacements: [
            PatternReplacement(
              from: RegExp('PLACEHOLDER'),
              to: '/*{{name}}*/',
            ),
          ],
        ),
        'use {{name}} here',
      );
    });

    test('honors x flags on liquid tags introduced by replacements', () {
      expect(
        resolvePatternContent(
          'use PLACEHOLDER here',
          replacements: [
            PatternReplacement(
              from: RegExp('PLACEHOLDER'),
              to: '/*x{{name}}x*/',
            ),
          ],
        ),
        'use{{name}}here',
      );
    });

    test('applies spacing groups after liquid tag unwrap', () {
      expect(
        resolvePatternContent(
          'keep\n'
          '/*{{name}}*/\n'
          '/*w 2v 4> w*/'
          'end\n',
        ),
        'keep\n'
        '{{name}}\n'
        '\n'
        '    end\n',
      );
    });

    test('expands mixed spacing group actions in the pipeline', () {
      expect(
        resolvePatternContent('a/*w 1v 2> w*/b'),
        'a\n  b',
      );
    });
  });
}
