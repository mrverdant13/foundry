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
      expect(report.lineDeletions, isEmpty);
      expect(report.replacements, isEmpty);
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
      expect(report.lineDeletions, isEmpty);
      expect(report.replacements, isEmpty);
      expect(report.fileCount, 3);
      expect(report.ignoredPaths, ['build/out.txt', 'scratch.tmp']);
      expect(report.topLevelEntries, containsAll(['.foundry', 'README.md']));
    });

    test('surfaces lineDeletions from the pattern marker', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_line_deletions_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await Directory(p.join(tempDir.path, '.foundry')).create();
      await File(p.join(tempDir.path, patternMarkerRelativePath)).writeAsString(
        '''
name: with_deletions
lineDeletions:
  - filePath: lib/main.dart
    ranges:
      - start: 1
        end: 2
''',
      );
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isTrue);
      expect(report.hasMarker, isTrue);
      expect(report.lineDeletions, hasLength(1));
      expect(report.lineDeletions.single.filePath, 'lib/main.dart');
      expect(report.lineDeletions.single.ranges, hasLength(1));
      expect(report.lineDeletions.single.ranges.single.start, 1);
      expect(report.lineDeletions.single.ranges.single.end, 2);
      expect(report.replacements, isEmpty);
    });

    test('surfaces replacements from the pattern marker', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_replacements_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await Directory(p.join(tempDir.path, '.foundry')).create();
      await File(p.join(tempDir.path, patternMarkerRelativePath)).writeAsString(
        '''
name: with_replacements
replacements:
  - from: ref_pkg
    to: "{{ package_name }}"
''',
      );
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isTrue);
      expect(report.hasMarker, isTrue);
      expect(report.replacements, hasLength(1));
      expect(report.replacements.single.from.pattern, 'ref_pkg');
      expect(report.replacements.single.to, '{{ package_name }}');
      expect(report.lineDeletions, isEmpty);
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

    test('returns a structured error when the top-level listing fails',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_list_top_level_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final previous = listPatternTopLevel;
      addTearDown(() => listPatternTopLevel = previous);
      listPatternTopLevel = (directory) {
        throw FileSystemException('Permission denied', directory.path);
      };

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isFalse);
      expect(report.rootPath, tempDir.absolute.path);
      expect(report.topLevelEntries, isEmpty);
      expect(report.fileCount, 0);
      expect(
        report.issues.single.message,
        'Could not list pattern directory: Permission denied',
      );
    });

    test('returns a structured error when recursive file listing fails',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_list_files_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final previous = listPatternFiles;
      addTearDown(() => listPatternFiles = previous);
      listPatternFiles = (rootPath) {
        throw FileSystemException('Permission denied', rootPath);
      };

      final report = await inspectPattern(tempDir.path);

      expect(report.isValid, isFalse);
      expect(report.rootPath, tempDir.absolute.path);
      expect(report.topLevelEntries, ['README.md']);
      expect(report.fileCount, 0);
      expect(
        report.issues.single.message,
        'Could not enumerate pattern files: Permission denied',
      );
    });

    test('returns a structured error when the marker file cannot be read',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'foundry_pattern_unreadable_marker_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await Directory(p.join(tempDir.path, '.foundry')).create();
      await File(p.join(tempDir.path, patternMarkerRelativePath)).writeAsString(
        'name: locked',
      );
      await File(p.join(tempDir.path, 'README.md')).writeAsString('# Pattern');

      final previous = readPatternMarkerFile;
      addTearDown(() => readPatternMarkerFile = previous);
      readPatternMarkerFile = (file) {
        throw FileSystemException('Permission denied', file.path);
      };

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
                'Could not read pattern marker: Permission denied',
              ),
        ),
      );
    });

    test(
      'surfaces a real unreadable marker file on POSIX hosts',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'foundry_pattern_chmod_marker_',
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
            isA<PatternIssue>().having(
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
