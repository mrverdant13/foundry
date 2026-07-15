import 'dart:io';

import 'package:path/path.dart' as p;

const _fixtureMarker = 'fixtures';

/// Relative paths from a working directory to an `e2e/e2e` tree with fixtures.
const _e2eRootCandidates = <String>[
  'e2e',
  'e2e/e2e',
  'packages/foundry_cli/e2e/e2e',
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

/// Returns the `foundry_core` package root by walking up from [start].
Directory foundryCorePackageRoot({Directory? start}) {
  var current = start ?? e2eTestRoot();
  while (true) {
    final candidate = Directory(
      p.join(current.path, 'packages', 'foundry_core'),
    );
    if (candidate.existsSync()) {
      return candidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate packages/foundry_core from ${current.path}',
      );
    }
    current = parent;
  }
}
