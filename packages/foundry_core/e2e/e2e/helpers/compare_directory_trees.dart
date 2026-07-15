import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Collects relative file paths under [root], using forward slashes.
List<String> listRelativeFiles(Directory root) {
  if (!root.existsSync()) {
    return [];
  }

  final files = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }

    files.add(
      p.relative(entity.path, from: root.path).replaceAll(r'\', '/'),
    );
  }
  files.sort();
  return files;
}

/// Asserts [actual] matches [expected] file-for-file.
void expectDirectoryTreesMatch({
  required Directory expected,
  required Directory actual,
}) {
  final expectedFiles = listRelativeFiles(expected);
  final actualFiles = listRelativeFiles(actual);

  expect(
    actualFiles,
    expectedFiles,
    reason: 'Directory trees differ.\n'
        'Expected only: '
        '${expectedFiles.where((path) => !actualFiles.contains(path)).join(', ')}\n'
        'Unexpected: '
        '${actualFiles.where((path) => !expectedFiles.contains(path)).join(', ')}',
  );

  for (final relativePath in expectedFiles) {
    final expectedContent =
        File(p.join(expected.path, relativePath)).readAsBytesSync();
    final actualContent =
        File(p.join(actual.path, relativePath)).readAsBytesSync();

    expect(
      actualContent,
      expectedContent,
      reason: 'Content mismatch in $relativePath',
    );
  }
}
