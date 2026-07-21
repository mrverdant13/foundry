import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_test_support.dart';

Future<void> _writePatternFile(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

/// Rewrites a derived mold's pubspec to a path dependency so [loadMold] works
/// offline against the local `foundry_core` package.
Future<void> _useLocalFoundryCore(Directory moldDirectory) async {
  final pubspec = File(p.join(moldDirectory.path, 'pubspec.yaml'));
  final nameMatch = RegExp(r'^name:\s+(\S+)\s*$', multiLine: true)
      .firstMatch(await pubspec.readAsString());
  final name = nameMatch?.group(1) ?? 'derived_mold';
  await writeMoldPubspec(
    directory: moldDirectory,
    name: name,
    description: 'A Foundry mold.',
  );
}

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_derive_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('sanitizeMoldName / isValidMoldName', () {
    test('accepts valid package names', () {
      expect(isValidMoldName('my_mold'), isTrue);
      expect(isValidMoldName('_private'), isTrue);
    });

    test('sanitizes mixed case and punctuation', () {
      expect(sanitizeMoldName('My App!'), 'my_app_');
      expect(sanitizeMoldName('2cool'), 'mold_2cool');
      expect(defaultMoldNameFromPath('/tmp/Hello-World'), 'hello_world');
    });
  });

  group('deriveMoldFromPattern', () {
    test('derives a loadable mold from a fixture pattern', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(
        pattern,
        '.foundry/pattern.yaml',
        'name: greeter_pattern\n'
            'ignore:\n'
            '  - "**/*.tmp"\n'
            '  - ".dart_tool/**"\n',
      );
      await _writePatternFile(
        pattern,
        'README.md',
        '# Hello {{ project_name }}\n',
      );
      await _writePatternFile(
        pattern,
        'lib/greeter.dart',
        'String greet() => "hi";\n',
      );
      await _writePatternFile(pattern, 'scratch.tmp', 'ignored');
      await _writePatternFile(
        pattern,
        '.dart_tool/package_config.json',
        '{}',
      );

      final destination = Directory(p.join(workDir.path, 'out_mold'));
      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: destination,
        tempParent: workDir,
      );

      expect(moldDir.path, destination.absolute.path);
      expect(
        File(p.join(moldDir.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'variables.dart')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(moldDir.path, 'hooks')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'template', 'README.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'template', 'lib', 'greeter.dart'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(moldDir.path, 'template', 'scratch.tmp')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(moldDir.path, 'template', '.foundry')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(moldDir.path, 'template', '.dart_tool')).existsSync(),
        isFalse,
      );

      final readme = await File(
        p.join(moldDir.path, 'template', 'README.md'),
      ).readAsString();
      expect(readme, '{% raw %}# Hello {{ project_name }}\n{% endraw %}');

      final pubspec = await File(
        p.join(moldDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('name: greeter_pattern'));
      expect(pubspec, contains('foundry_core: ^'));

      await _useLocalFoundryCore(moldDir);
      final mold = await loadMold(moldDir.path);
      expect(mold.name, 'greeter_pattern');
      expect(mold.variableGroup.variables.keys, contains('project_name'));

      final report = await inspectMold(moldDir.path);
      expect(report.isValid, isTrue);
    });

    test('fails when destination exists and force is false', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');
      final destination = Directory(p.join(workDir.path, 'existing'))
        ..createSync();
      File(p.join(destination.path, 'stale.txt')).writeAsStringSync('stale');

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: destination,
          name: 'sample_mold',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      expect(
        File(p.join(destination.path, 'stale.txt')).existsSync(),
        isTrue,
      );
    });

    test('overwrites destination when force is true', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'fresh');
      final destination = Directory(p.join(workDir.path, 'existing'))
        ..createSync();
      File(p.join(destination.path, 'stale.txt')).writeAsStringSync('stale');

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: destination,
        name: 'forced_mold',
        force: true,
        tempParent: workDir,
      );

      expect(
        File(p.join(moldDir.path, 'stale.txt')).existsSync(),
        isFalse,
      );
      expect(
        await File(p.join(moldDir.path, 'template', 'README.md'))
            .readAsString(),
        'fresh',
      );
    });

    test('fails for a missing pattern path', () async {
      await expectLater(
        deriveMoldFromPattern(
          patternPath: p.join(workDir.path, 'missing'),
          destination: Directory(p.join(workDir.path, 'out')),
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('invalid'),
          ),
        ),
      );
    });

    test('copies binary files into template unchanged', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      final binary = File(p.join(pattern.path, 'blob.bin'))
        ..writeAsBytesSync(const [0x00, 0x01, 0x02, 0xff]);

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'out')),
        name: 'binary_mold',
        tempParent: workDir,
      );

      expect(
        await File(p.join(moldDir.path, 'template', 'blob.bin')).readAsBytes(),
        await binary.readAsBytes(),
      );
    });

    test('cleans up staging directories after success and failure', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');
      final tempParent = Directory(p.join(workDir.path, 'temps'))..createSync();

      await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'ok_out')),
        name: 'ok_mold',
        tempParent: tempParent,
      );

      await expectLater(
        deriveMoldFromPattern(
          patternPath: p.join(workDir.path, 'missing'),
          destination: Directory(p.join(workDir.path, 'fail_out')),
          tempParent: tempParent,
        ),
        throwsA(isA<MoldDeriveException>()),
      );

      final leftover = tempParent.listSync().whereType<Directory>().where(
            (dir) => p.basename(dir.path).startsWith('foundry_mold_derive_'),
          );
      expect(leftover, isEmpty);
    });

    test('rejects destination inside the pattern directory', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(pattern.path, 'nested_mold')),
          name: 'nested_mold',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('cannot be inside'),
          ),
        ),
      );
    });
  });
}
