import 'package:foundry_cli/src/display_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('formatDisplayPath', () {
    final cwd = p.join(p.separator, 'tmp', 'foundry_cwd');

    test('prefers a ./ relative path when under cwd', () {
      final output = p.join(cwd, 'my_app');

      expect(
        formatDisplayPath(output, cwd: cwd),
        '.${p.separator}${p.join('my_app')}',
      );
    });

    test('formats nested paths under cwd as relative', () {
      final output = p.join(cwd, 'packages', 'my_api');

      expect(
        formatDisplayPath(output, cwd: cwd),
        '.${p.separator}${p.join('packages', 'my_api')}',
      );
    });

    test('resolves relative input against cwd before formatting', () {
      expect(
        formatDisplayPath('out', cwd: cwd),
        '.${p.separator}${p.join('out')}',
      );
    });

    test('returns absolute path when outside cwd', () {
      final outside = p.join(p.separator, 'other', 'project');

      expect(formatDisplayPath(outside, cwd: cwd), p.normalize(outside));
    });

    test('returns absolute path when escaping cwd via parent segments', () {
      final sibling = p.join(p.separator, 'tmp', 'sibling');

      expect(formatDisplayPath(sibling, cwd: cwd), p.normalize(sibling));
    });

    test('formats cwd itself as ./', () {
      expect(formatDisplayPath(cwd, cwd: cwd), '.${p.separator}');
    });
  });
}
