import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_template_relative_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveTemplateRelativePath', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('foundry_path_resolve_');
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns the joined path when replacements are empty', () {
      final resolved = resolveTemplateRelativePath(
        relativePosixPath: 'lib/main.dart',
        templateRootPath: tempRoot.path,
        replacements: const [],
      );
      expect(resolved, p.join(tempRoot.path, 'lib', 'main.dart'));
    });

    test('applies path replacements before joining', () {
      final resolved = resolveTemplateRelativePath(
        relativePosixPath: 'lib/ref_pkg.dart',
        templateRootPath: tempRoot.path,
        replacements: [
          PatternReplacement(
            from: RegExp('ref_pkg'),
            to: '{{ package_name }}',
          ),
        ],
      );
      expect(
        resolved,
        p.join(tempRoot.path, 'lib', '{{ package_name }}.dart'),
      );
    });

    test('rejects absolute resolved paths', () {
      expect(
        () => resolveTemplateRelativePath(
          relativePosixPath: 'lib/main.dart',
          templateRootPath: tempRoot.path,
          replacements: [
            PatternReplacement(
              from: RegExp(r'lib/main\.dart'),
              to: '/etc/passwd',
            ),
          ],
        ),
        throwsA(
          isA<TemplatePathReplacementException>().having(
            (error) => error.message,
            'message',
            contains('absolute path'),
          ),
        ),
      );
    });

    test('rejects paths that escape the template root', () {
      expect(
        () => resolveTemplateRelativePath(
          relativePosixPath: 'lib/main.dart',
          templateRootPath: tempRoot.path,
          replacements: [
            PatternReplacement(
              from: RegExp(r'lib/main\.dart'),
              to: '../outside.txt',
            ),
          ],
        ),
        throwsA(
          isA<TemplatePathReplacementException>().having(
            (error) => error.message,
            'message',
            contains('outside the template directory'),
          ),
        ),
      );
    });
  });
}
