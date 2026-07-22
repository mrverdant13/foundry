import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_derive.dart';
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
  late Future<void> Function({
    required Directory staging,
    required Directory destination,
  }) originalCommit;
  late Future<PatternInspectionReport> Function(String patternPath)
      originalInspect;
  late FileSystemEntityType Function(String path) originalResolveType;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_mold_derive_');
    originalCommit = commitDerivedMoldStaging;
    originalInspect = inspectPatternForDerive;
    originalResolveType = resolveDeriveDestinationType;
  });

  tearDown(() {
    commitDerivedMoldStaging = originalCommit;
    inspectPatternForDerive = originalInspect;
    resolveDeriveDestinationType = originalResolveType;
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('sanitizeMoldName / isValidMoldName', () {
    test('accepts valid package names', () {
      expect(isValidMoldName('my_mold'), isTrue);
      expect(isValidMoldName('_private'), isTrue);
      expect(isValidMoldName('Bad Name'), isFalse);
      expect(isValidMoldName('123'), isFalse);
    });

    test('sanitizes mixed case and punctuation', () {
      expect(sanitizeMoldName('My App!'), 'my_app_');
      expect(sanitizeMoldName('2cool'), 'mold_2cool');
      expect(sanitizeMoldName('!!!'), '___');
      expect(sanitizeMoldName(''), 'mold');
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
      expect(readme, '# Hello {{ "{{" }} project_name }}\n');

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

    test('applies marker lineDeletions when writing template/', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(
        pattern,
        '.foundry/pattern.yaml',
        'name: deletions_pattern\n'
            'lineDeletions:\n'
            '  - filePath: lib/greeter.dart\n'
            '    ranges:\n'
            '      - start: 1\n'
            '        end: 2\n'
            '  - filePath: missing.dart\n'
            '    ranges:\n'
            '      - start: 0\n'
            '        end: 0\n',
      );
      await _writePatternFile(
        pattern,
        'lib/greeter.dart',
        'line0\n'
            'line1-drop\n'
            'line2-drop\n'
            'line3\n',
      );
      await _writePatternFile(
        pattern,
        'README.md',
        'keep-all\n'
            'also-keep\n',
      );

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'out_mold')),
        tempParent: workDir,
      );

      final greeter = await File(
        p.join(moldDir.path, 'template', 'lib', 'greeter.dart'),
      ).readAsString();
      expect(greeter, 'line0\nline3\n');

      final readme = await File(
        p.join(moldDir.path, 'template', 'README.md'),
      ).readAsString();
      expect(readme, 'keep-all\nalso-keep\n');
    });

    test('applies marker replacements to paths and contents', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(
        pattern,
        '.foundry/pattern.yaml',
        'name: replacements_pattern\n'
            'replacements:\n'
            '  - from: ref_pkg\n'
            '    to: "{{ package_name }}"\n'
            '  - from: "Foo(.*)"\n'
            '    to: "Bar\${1}"\n',
      );
      await _writePatternFile(
        pattern,
        'lib/ref_pkg.dart',
        'library ref_pkg;\n'
            'class FooWidget {}\n'
            'const keep = "{{ already_liquid }}";\n',
      );
      await _writePatternFile(pattern, 'README.md', 'plain readme\n');

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'out_mold')),
        tempParent: workDir,
      );

      expect(
        File(
          p.join(moldDir.path, 'template', 'lib', 'ref_pkg.dart'),
        ).existsSync(),
        isFalse,
      );
      final renamed = await File(
        p.join(moldDir.path, 'template', 'lib', '{{ package_name }}.dart'),
      ).readAsString();
      expect(
        renamed,
        'library {{ package_name }};\n'
        'class BarWidget {}\n'
        r'const keep = "{{ "{{" }} already_liquid }}";'
        '\n',
      );

      final readme = await File(
        p.join(moldDir.path, 'template', 'README.md'),
      ).readAsString();
      expect(readme, 'plain readme\n');
    });

    test('rejects path replacements that escape the template root', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(
        pattern,
        '.foundry/pattern.yaml',
        'name: bad_path_pattern\n'
            'replacements:\n'
            '  - from: "README.md"\n'
            '    to: "../escape.txt"\n',
      );
      await _writePatternFile(pattern, 'README.md', 'x\n');

      expect(
        () => deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out_mold')),
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('outside the template directory'),
          ),
        ),
      );
    });

    test('names the mold from the pattern directory basename', () async {
      final pattern = Directory(p.join(workDir.path, 'hello_world'))
        ..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'out')),
        tempParent: workDir,
      );

      final pubspec = await File(
        p.join(moldDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('name: hello_world'));
    });

    test('falls back to destination basename when pattern is named mold',
        () async {
      final pattern = Directory(p.join(workDir.path, 'mold'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(p.join(workDir.path, 'from_dest')),
        tempParent: workDir,
      );

      final pubspec = await File(
        p.join(moldDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('name: from_dest'));
    });

    test('rejects an invalid explicit mold name', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out')),
          name: 'Not Valid!',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('not a valid package name'),
          ),
        ),
      );
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

    test('fails when destination is a file and force is false', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');
      final destinationFile = File(p.join(workDir.path, 'existing_file'))
        ..writeAsStringSync('not a directory');

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(destinationFile.path),
          name: 'file_dest_mold',
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
      expect(destinationFile.existsSync(), isTrue);
      expect(await destinationFile.readAsString(), 'not a directory');
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

    test('overwrites a file destination when force is true', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'fresh');
      final destinationFile = File(p.join(workDir.path, 'existing_file'))
        ..writeAsStringSync('not a directory');

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(destinationFile.path),
        name: 'forced_file_mold',
        force: true,
        tempParent: workDir,
      );

      expect(FileSystemEntity.isDirectorySync(moldDir.path), isTrue);
      expect(destinationFile.existsSync(), isFalse);
      expect(
        await File(p.join(moldDir.path, 'template', 'README.md'))
            .readAsString(),
        'fresh',
      );
    });

    test('overwrites a symlink destination when force is true', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'fresh');
      final linkTarget = File(p.join(workDir.path, 'link_target'))
        ..writeAsStringSync('target');
      final destinationLink = Link(p.join(workDir.path, 'existing_link'))
        ..createSync(linkTarget.path);

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(destinationLink.path),
        name: 'forced_link_mold',
        force: true,
        tempParent: workDir,
      );

      expect(FileSystemEntity.isDirectorySync(moldDir.path), isTrue);
      expect(
        FileSystemEntity.typeSync(destinationLink.path, followLinks: false),
        FileSystemEntityType.directory,
      );
      expect(linkTarget.existsSync(), isTrue);
      expect(await linkTarget.readAsString(), 'target');
      expect(
        await File(p.join(moldDir.path, 'template', 'README.md'))
            .readAsString(),
        'fresh',
      );
    });

    test('fails when destination is a symlink and force is false', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'plain');
      final linkTarget = File(p.join(workDir.path, 'link_target'))
        ..writeAsStringSync('target');
      final destinationLink = Link(p.join(workDir.path, 'existing_link'))
        ..createSync(linkTarget.path);

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(destinationLink.path),
          name: 'link_dest_mold',
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
        FileSystemEntity.typeSync(destinationLink.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await linkTarget.readAsString(), 'target');
    });

    test('overwrites a pipe-typed destination when force is true', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'fresh');
      final destinationFile = File(p.join(workDir.path, 'existing_pipe'))
        ..writeAsStringSync('pipe stand-in');
      resolveDeriveDestinationType = (_) => FileSystemEntityType.pipe;

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(destinationFile.path),
        name: 'forced_pipe_mold',
        force: true,
        tempParent: workDir,
      );

      expect(FileSystemEntity.isDirectorySync(moldDir.path), isTrue);
      expect(
        await File(p.join(moldDir.path, 'template', 'README.md'))
            .readAsString(),
        'fresh',
      );
    });

    test('overwrites a unix-domain-socket-typed destination when force is true',
        () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'fresh');
      final destinationFile = File(p.join(workDir.path, 'existing_sock'))
        ..writeAsStringSync('sock stand-in');
      resolveDeriveDestinationType = (_) => FileSystemEntityType.unixDomainSock;

      final moldDir = await deriveMoldFromPattern(
        patternPath: pattern.path,
        destination: Directory(destinationFile.path),
        name: 'forced_sock_mold',
        force: true,
        tempParent: workDir,
      );

      expect(FileSystemEntity.isDirectorySync(moldDir.path), isTrue);
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

    test('fails when pattern inspection reports empty error messages',
        () async {
      inspectPatternForDerive = (patternPath) async {
        return PatternInspectionReport(
          rootPath: patternPath,
          issues: const [
            PatternIssue(
              severity: PatternIssueSeverity.error,
              path: 'pattern',
              message: '',
            ),
          ],
        );
      };

      await expectLater(
        deriveMoldFromPattern(
          patternPath: p.join(workDir.path, 'ignored'),
          destination: Directory(p.join(workDir.path, 'out')),
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            contains('could not be inspected'),
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

    test('rejects destination equal to the pattern directory', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: pattern,
          name: 'same_path',
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

    test('rethrows MoldDeriveException from commit staging', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      commitDerivedMoldStaging = ({
        required staging,
        required destination,
      }) async {
        throw const MoldDeriveException('commit refused');
      };

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out')),
          name: 'commit_mold',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            'commit refused',
          ),
        ),
      );
    });

    test('wraps FileSystemException from commit staging with a path', () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      commitDerivedMoldStaging = ({
        required staging,
        required destination,
      }) async {
        throw const FileSystemException('Permission denied', '/tmp/blocked');
      };

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out')),
          name: 'fs_mold',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Failed to derive mold'),
              contains('Permission denied'),
              contains('/tmp/blocked'),
            ),
          ),
        ),
      );
    });

    test('wraps FileSystemException from commit staging without a path',
        () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      commitDerivedMoldStaging = ({
        required staging,
        required destination,
      }) async {
        throw const FileSystemException('Disk full', null);
      };

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out')),
          name: 'fs_mold_no_path',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Failed to derive mold'),
              contains('Disk full'),
              isNot(contains('(')),
            ),
          ),
        ),
      );
    });

    test('wraps FileSystemException from commit staging with an empty path',
        () async {
      final pattern = Directory(p.join(workDir.path, 'pattern'))..createSync();
      await _writePatternFile(pattern, 'README.md', 'ok');

      commitDerivedMoldStaging = ({
        required staging,
        required destination,
      }) async {
        throw const FileSystemException('Disk full');
      };

      await expectLater(
        deriveMoldFromPattern(
          patternPath: pattern.path,
          destination: Directory(p.join(workDir.path, 'out_empty_path')),
          name: 'fs_mold_empty_path',
          tempParent: workDir,
        ),
        throwsA(
          isA<MoldDeriveException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Failed to derive mold'),
              contains('Disk full'),
              isNot(contains('(')),
            ),
          ),
        ),
      );
    });
  });
}
