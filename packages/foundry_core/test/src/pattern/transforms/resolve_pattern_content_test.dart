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
              from: RegExp(r'Foo(.*)'),
              to: r'Bar${1}',
            ),
          ],
        ),
        'BarWidget',
      );
    });
  });
}
