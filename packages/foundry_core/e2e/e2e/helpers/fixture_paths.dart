import 'dart:io';

import 'package:path/path.dart' as p;

const _fixtureMarker = 'fixtures';

/// Relative paths from a working directory to an `e2e/e2e` tree with fixtures.
const _e2eRootCandidates = <String>[
  'e2e',
  'e2e/e2e',
  'packages/foundry_core/e2e/e2e',
];

/// Returns the `e2e/e2e` directory that contains fixture trees.
Directory e2eTestRoot() {
  var current = Directory.current;
  while (true) {
    for (final relative in _e2eRootCandidates) {
      final root = Directory(p.join(current.path, relative));
      if (Directory(p.join(root.path, _fixtureMarker)).existsSync()) {
        return root;
      }
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Could not locate e2e fixtures from ${Directory.current.path}',
  );
}

/// Returns the absolute path to a fixture directory under [e2eTestRoot].
String fixturePath(String relativePath) {
  return p.join(e2eTestRoot().path, _fixtureMarker, relativePath);
}
