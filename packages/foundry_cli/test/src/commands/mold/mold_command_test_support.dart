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

/// Writes a minimal mold source (`pubspec.yaml` naming the mold, plus a
/// `template/` file) into [directory], suitable as an import source. Import
/// only reads the pubspec `name` field and copies files, so this does not
/// need to be a loadable mold.
Future<void> writeImportSourceMold({
  required Directory directory,
  required String name,
}) async {
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: $name
description: A mold used for import command tests.
version: 0.0.1
''');
  final templateDir = Directory(p.join(directory.path, 'template'))
    ..createSync();
  await File(p.join(templateDir.path, 'README.md')).writeAsString('# $name\n');
}

Future<ProcessResult> _git(List<String> args, {required String cwd}) {
  return Process.run('git', args, workingDirectory: cwd);
}

/// Initializes a local git repository at [repoDir] with an import-source
/// mold at `<repoDir>/<subPath>` and commits it, so tests can clone from a
/// `file://` remote without hitting the network.
Future<void> initMoldGitRepo(
  Directory repoDir, {
  required String moldName,
  String subPath = '.',
}) async {
  final moldDir = subPath == '.'
      ? repoDir
      : (Directory(p.join(repoDir.path, subPath))..createSync(recursive: true));
  await writeImportSourceMold(directory: moldDir, name: moldName);

  await _git(['init', '--quiet'], cwd: repoDir.path);
  await _git(
    ['-c', 'user.email=test@example.com', '-c', 'user.name=Test', 'add', '-A'],
    cwd: repoDir.path,
  );
  final commitResult = await _git(
    [
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Test',
      'commit',
      '--quiet',
      '-m',
      'Initial commit',
    ],
    cwd: repoDir.path,
  );
  if (commitResult.exitCode != 0) {
    throw StateError(
      'Failed to set up git fixture repo: '
      '${commitResult.stdout}${commitResult.stderr}',
    );
  }
}
