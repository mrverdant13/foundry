import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the `foundry_core` package root by walking up from [start].
Directory foundryCorePackageRoot({Directory? start}) {
  var current = start ?? Directory.current;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(r'^name:\s+foundry_core\s*$', multiLine: true)
            .hasMatch(pubspec.readAsStringSync())) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate foundry_core package root from ${current.path}',
      );
    }
    current = parent;
  }
}

/// Returns the workspace `package_config.json` used to resolve `foundry_core`.
String workspacePackageConfigPath({Directory? start}) {
  var current = start ?? foundryCorePackageRoot();
  while (true) {
    final config =
        File(p.join(current.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      return config.absolute.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate workspace package_config.json from ${current.path}',
      );
    }
    current = parent;
  }
}

/// Writes a minimal mold `pubspec.yaml` into [directory].
Future<void> writeMoldPubspec({
  required Directory directory,
  required String name,
  required String description,
}) async {
  final coreRoot = foundryCorePackageRoot();
  final corePath = coreRoot.absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: $name
description: $description
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: $corePath
''');
}
