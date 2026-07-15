import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the `e2e/e2e` directory that contains fixture trees.
Directory e2eTestRoot({String? from}) {
  final start = from ?? Platform.script.toFilePath();
  final file = File(start);
  var current = file.existsSync() ? file.parent : Directory(start);

  while (true) {
    final candidate = Directory(p.join(current.path, 'fixtures'));
    if (candidate.existsSync()) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate e2e test root from $start');
    }
    current = parent;
  }
}

/// Returns the absolute path to a fixture directory under [e2eTestRoot].
String fixturePath(String relativePath, {String? from}) {
  return p.join(e2eTestRoot(from: from).path, 'fixtures', relativePath);
}
