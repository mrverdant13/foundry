import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('inspectPattern', () {
    test('summarizes a valid pattern directory without a marker', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_no_marker_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');
      await Directory(p.join(tempDir.path, 'lib')).create();
      await File(p.join(tempDir.path, 'lib', 'main.dart')).writeAsString(
        'void main() {}',
      );

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isTrue);
      expect(report.hasMarker, isFalse);
      expect(report.name, isNull);
      expect(report.ignoreGlobs, isEmpty);
      expect(report.ignoredPaths, isEmpty);
      expect(report.fileCount, 2);
      expect(report.topLevelEntries, ['README.md', 'lib']);
      expect(report.rootPath, tempDir.absolute.path);
    });

    test('applies ignore globs from the pattern marker', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_marker_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await Directory(p.join(tempDir.path, '.foundry')).create();
      await File(p.join(tempDir.path, patternMarkerRelativePath)).writeAsString(
        '''
name: marked_pattern
ignore:
  - build/**
  - '**/*.tmp'
''',
      );
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');
      await Directory(p.join(tempDir.path, 'build')).create();
      await File(p.join(tempDir.path, 'build', 'out.txt')).writeAsString('x');
      await File(p.join(tempDir.path, 'scratch.tmp')).writeAsString('tmp');
      await File(p.join(tempDir.path, 'keep.txt')).writeAsString('keep');

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isTrue);
      expect(report.hasMarker, isTrue);
      expect(report.name, 'marked_pattern');
      expect(report.ignoreGlobs, ['build/**', '**/*.tmp']);
      expect(report.fileCount, 3);
      expect(report.ignoredPaths, ['build/out.txt', 'scratch.tmp']);
      expect(report.topLevelEntries, containsAll(['.foundry', 'README.md']));
    });

    test('returns a structured error when the path is missing', () async {
      final missingPath = p.join(
        Directory.systemTemp.path,
        'foundry_pattern_missing_${DateTime.now().microsecondsSinceEpoch}',
      );

      final report = await inspectPattern(missingPath);

      expect(report.isValid, isFalse);
      expect(report.hasErrors, isTrue);
      expect(report.fileCount, 0);
      expect(report.topLevelEntries, isEmpty);
      expect(
        report.issues,
        contains(
          isA<PatternIssue>()
              .having(
                (issue) => issue.severity,
                'severity',
                PatternIssueSeverity.error,
              )
              .having((issue) => issue.path, 'path', missingPath)
              .having(
                (issue) => issue.message,
                'message',
                contains('does not exist'),
              ),
        ),
      );
    });

    test('returns a structured error when the path is a file', () async {
      final tempFile = await File(
        p.join(
          Directory.systemTemp.path,
          'foundry_pattern_file_${DateTime.now().microsecondsSinceEpoch}.txt',
        ),
      ).create();
      addTearDown(tempFile.deleteSync);

      final report = await inspectPattern(tempFile.path);

      expect(report.isValid, isFalse);
      expect(
        report.issues.single.message,
        contains('not a directory'),
      );
    });

    test('reports marker parse failures without dropping the tree summary',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_bad_marker_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await Directory(p.join(tempDir.path, '.foundry')).create();
      await File(p.join(tempDir.path, patternMarkerRelativePath)).writeAsString(
        'name: [unterminated',
      );
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isFalse);
      expect(report.hasMarker, isTrue);
      expect(report.fileCount, 2);
      expect(report.topLevelEntries, contains('README.md'));
      expect(report.issues, isNotEmpty);
      expect(
        report.issues.first.severity,
        PatternIssueSeverity.error,
      );
    });

    test('returns a structured error when the path cannot be inspected',
        () async {
      final previous = resolvePatternEntityType;
      addTearDown(() => resolvePatternEntityType = previous);

      resolvePatternEntityType = (path) {
        throw FileSystemException('Permission denied', path);
      };

      const path = '/tmp/unreadable-pattern';
      final report = await inspectPattern(path);

      expect(report.isValid, isFalse);
      expect(report.rootPath, path);
      expect(
        report.issues.single.message,
        'Could not inspect pattern path: Permission denied',
      );
    });

    test(
      'returns a structured error when the marker file cannot be read',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'foundry_pattern_unreadable_marker_',
        );
        addTearDown(() {
          Process.runSync('chmod', ['-R', 'u+rwX', tempDir.path]);
          tempDir.deleteSync(recursive: true);
        });

        await Directory(p.join(tempDir.path, '.foundry')).create();
        final markerFile = File(
          p.join(tempDir.path, patternMarkerRelativePath),
        );
        await markerFile.writeAsString('name: locked');
        await File(p.join(tempDir.path, 'README.md')).writeAsString(
          '# Pattern',
        );

        final chmod = Process.runSync('chmod', ['a=', markerFile.path]);
        expect(chmod.exitCode, 0);

        final report = await inspectPattern(tempDir.path);

        expect(report.isValid, isFalse);
        expect(report.hasMarker, isTrue);
        expect(
          report.issues,
          contains(
            isA<PatternIssue>()
                .having(
                  (issue) => issue.severity,
                  'severity',
                  PatternIssueSeverity.error,
                )
                .having(
                  (issue) => issue.message,
                  'message',
                  contains('Could not read pattern marker'),
                ),
          ),
        );
      },
      skip: !Platform.isLinux && !Platform.isMacOS,
    );
  });
}
