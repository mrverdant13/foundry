import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the `e2e/e2e` directory that contains fixture trees.
Directory e2eTestRoot() {
  final candidates = <Directory>[
    Directory(p.join(Directory.current.path, 'e2e')),
    Directory(
      p.join(
        Directory.current.path,
        'packages',
        'foundry_core',
        'e2e',
        'e2e',
      ),
    ),
  ];

  for (final candidate in candidates) {
    if (Directory(p.join(candidate.path, 'fixtures')).existsSync()) {
      return candidate;
    }
  }

  throw StateError(
    'Could not locate e2e fixtures from ${Directory.current.path}',
  );
}

/// Returns the absolute path to a fixture directory under [e2eTestRoot].
String fixturePath(String relativePath) {
  return p.join(e2eTestRoot().path, 'fixtures', relativePath);
}
