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
        '{% raw %}Hello {{ name }}{% endraw %}',
      );
    });

    test('liquidizes content that contains Liquid tags', () {
      expect(
        resolvePatternContent('{% if true %}yes{% endif %}'),
        '{% raw %}{% if true %}yes{% endif %}{% endraw %}',
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
        '{% raw %}Hello {{ name }}\n{% endraw %}',
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
  });
}
