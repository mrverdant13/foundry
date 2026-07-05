import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the `foundry_core` package root by walking up from [start].
Directory foundryCorePackageRoot({Directory? start}) {
  var current = start ?? Directory.current;
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

/// Writes a minimal, loadable mold (`pubspec.yaml`, `variables.dart`, and
/// `template/`) into [directory], depending on `foundry_core` via a local
/// path so `dart pub get` resolves without network access.
Future<void> writeInspectableMold({
  required Directory directory,
  required String name,
}) async {
  final corePath = foundryCorePackageRoot().absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: $name
description: A mold used for command tests.
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: $corePath
''');
  await File(p.join(directory.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''');
  await Directory(p.join(directory.path, 'template')).create();
}
