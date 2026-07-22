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
  });
}
