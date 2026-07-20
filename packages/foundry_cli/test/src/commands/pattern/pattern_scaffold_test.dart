import 'dart:io';

import 'package:foundry_cli/src/commands/pattern/pattern_scaffold.dart';
import 'package:foundry_core/foundry_core.dart'
    show parsePatternMarker, patternMarkerRelativePath;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_pattern_scaffold_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('isValidPatternName', () {
    test('accepts non-empty names', () {
      expect(isValidPatternName('demo_pattern'), isTrue);
      expect(isValidPatternName(' Demo '), isTrue);
    });

    test('rejects empty or whitespace-only names', () {
      expect(isValidPatternName(''), isFalse);
      expect(isValidPatternName('   '), isFalse);
    });
  });

  group('defaultPatternName', () {
    test('uses the directory basename', () {
      final dir = Directory(p.join(workDir.path, 'my-pattern'));
      expect(defaultPatternName(dir), 'my-pattern');
    });
  });

  group('PatternScaffoldException', () {
    test('toString returns the message', () {
      const exception = PatternScaffoldException('boom');

      expect(exception.toString(), 'boom');
    });
  });

  group('scaffoldPattern', () {
    test('creates the pattern marker and README', () async {
      await scaffoldPattern(directory: workDir, name: 'demo_pattern');

      final marker = File(p.join(workDir.path, patternMarkerRelativePath));
      expect(marker.existsSync(), isTrue);
      final markerContents = marker.readAsStringSync();
      expect(markerContents, contains('name: "demo_pattern"'));
      expect(markerContents, contains('.dart_tool/**'));
      expect(markerContents, contains('.git/**'));
      expect(markerContents, contains('build/**'));

      final readme = File(p.join(workDir.path, 'README.md'));
      expect(readme.existsSync(), isTrue);
      expect(readme.readAsStringSync(), contains('# demo_pattern'));
      expect(readme.readAsStringSync(), contains('foundry pattern inspect'));
    });

    test('trims the pattern name before writing', () async {
      await scaffoldPattern(directory: workDir, name: '  trimmed  ');

      final marker = File(p.join(workDir.path, patternMarkerRelativePath));
      expect(marker.readAsStringSync(), contains('name: "trimmed"'));
    });

    test('quotes YAML-significant characters in the marker name', () async {
      const awkwardName = r'a: b # "quoted" \ slash';
      await scaffoldPattern(directory: workDir, name: awkwardName);

      final markerPath = p.join(workDir.path, patternMarkerRelativePath);
      final markerContents = File(markerPath).readAsStringSync();
      expect(
        markerContents,
        contains(r'name: "a: b # \"quoted\" \\ slash"'),
      );

      final parsed = parsePatternMarker(
        yamlContent: markerContents,
        sourcePath: markerPath,
      );
      expect(parsed.name, awkwardName);
    });

    test('creates the target directory when it does not exist yet', () async {
      final target = Directory(p.join(workDir.path, 'nested', 'pattern_dir'));

      await scaffoldPattern(directory: target, name: 'nested_pattern');

      expect(
        File(p.join(target.path, patternMarkerRelativePath)).existsSync(),
        isTrue,
      );
      expect(File(p.join(target.path, 'README.md')).existsSync(), isTrue);
    });

    test('fails when the pattern marker already exists', () async {
      Directory(p.join(workDir.path, '.foundry')).createSync();
      File(p.join(workDir.path, patternMarkerRelativePath)).createSync();

      await expectLater(
        scaffoldPattern(directory: workDir, name: 'demo_pattern'),
        throwsA(
          isA<PatternScaffoldException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('already exists'),
              contains(patternMarkerRelativePath),
            ),
          ),
        ),
      );
      expect(File(p.join(workDir.path, 'README.md')).existsSync(), isFalse);
    });

    test('fails without writing anything when README.md already exists',
        () async {
      File(p.join(workDir.path, 'README.md')).createSync();

      await expectLater(
        scaffoldPattern(directory: workDir, name: 'demo_pattern'),
        throwsA(
          isA<PatternScaffoldException>().having(
            (error) => error.message,
            'message',
            allOf(contains('already exists'), contains('README.md')),
          ),
        ),
      );
      expect(
        File(p.join(workDir.path, patternMarkerRelativePath)).existsSync(),
        isFalse,
      );
    });

    test('wraps a FileSystemException when .foundry exists as a file',
        () async {
      File(p.join(workDir.path, '.foundry')).createSync();

      await expectLater(
        scaffoldPattern(directory: workDir, name: 'demo_pattern'),
        throwsA(
          isA<PatternScaffoldException>().having(
            (error) => error.message,
            'message',
            contains('Failed to scaffold pattern'),
          ),
        ),
      );
    });
  });
}
