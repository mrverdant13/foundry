import 'package:foundry_core/src/pattern/pattern_ignore.dart';
import 'package:test/test.dart';

void main() {
  group('isPatternPathIgnored', () {
    test('returns false when ignore globs are empty', () {
      expect(isPatternPathIgnored('lib/main.dart', const []), isFalse);
    });

    test('matches **/ prefixes at the pattern root', () {
      expect(
        isPatternPathIgnored('scratch.tmp', const ['**/*.tmp']),
        isTrue,
      );
    });

    test('matches nested paths against authored globs', () {
      expect(
        isPatternPathIgnored('build/out.bin', const ['build/**']),
        isTrue,
      );
      expect(
        isPatternPathIgnored('lib/main.dart', const ['build/**']),
        isFalse,
      );
    });
  });
}
