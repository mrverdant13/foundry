import 'dart:io';

import 'package:path/path.dart' as p;

import 'mold/mold_command_test_support.dart';

/// Writes a mold with a `project_name` string variable, one template file
/// that echoes it, and (optionally) a prepare hook, suitable for exercising
/// `foundry cast`.
Future<void> writeCastableMold({
  required Directory directory,
  required String name,
  bool withHooks = false,
}) async {
  final corePath = foundryCorePackageRoot().absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: $name
description: A mold used for cast command tests.
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
  final templateDir = Directory(p.join(directory.path, 'template'))
    ..createSync();
  await File(
    p.join(templateDir.path, 'README.md'),
  ).writeAsString('# {{ project_name }}\n');

  if (withHooks) {
    final hooksDir = Directory(p.join(directory.path, 'hooks'))..createSync();
    await File(p.join(hooksDir.path, 'prepare.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('from_prepare', 'yes');
}
''');
  }
}

/// Writes a mold with a finish hook that creates `finish_marker.txt` in the
/// output directory.
Future<void> writeCastableMoldWithFinishHook({
  required Directory directory,
  required String name,
}) async {
  await writeCastableMold(directory: directory, name: name);
  final hooksDir = Directory(p.join(directory.path, 'hooks'))..createSync();
  await File(p.join(hooksDir.path, 'finish.dart')).writeAsString('''
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  await File('finish_marker.txt').writeAsString('done');
}
''');
}

/// Writes a mold whose prepare hook fails during casting.
Future<void> writeHookFailingMold({
  required Directory directory,
  required String name,
}) async {
  await writeCastableMold(directory: directory, name: name);
  final hooksDir = Directory(p.join(directory.path, 'hooks'))..createSync();
  await File(p.join(hooksDir.path, 'prepare.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  throw StateError('prepare hook failed');
}
''');
}

/// Writes a mold whose finish hook fails during casting.
Future<void> writeFinishHookFailingMold({
  required Directory directory,
  required String name,
}) async {
  await writeCastableMoldWithFinishHook(directory: directory, name: name);
  await File(p.join(directory.path, 'hooks', 'finish.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  throw const FoundryHookException('finish always fails');
}
''');
}

/// Writes a mold whose prepare hook creates a file under `--output`.
Future<void> writeCastableMoldWithPrepareArtifact({
  required Directory directory,
  required String name,
}) async {
  await writeCastableMold(directory: directory, name: name);
  final hooksDir = Directory(p.join(directory.path, 'hooks'))..createSync();
  await File(p.join(hooksDir.path, 'prepare.dart')).writeAsString('''
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  await File('prepare_artifact.txt').writeAsString('prepared');
}
''');
}

/// Writes a mold whose template cannot be rendered.
Future<void> writeBrokenTemplateMold({
  required Directory directory,
  required String name,
}) async {
  await writeCastableMold(directory: directory, name: name);
  await File(
    p.join(directory.path, 'template', 'README.md'),
  ).writeAsString('# {{ project_name\n');
}

/// Writes a castable mold with a string and int variable for batch parse tests.
Future<void> writeNumericCastableMold({
  required Directory directory,
  required String name,
}) async {
  final corePath = foundryCorePackageRoot().absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: $name
description: A mold used for cast command tests.
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
    'port': FoundryIntVariable(label: 'Port'),
  },
);
''');
  final templateDir = Directory(p.join(directory.path, 'template'))
    ..createSync();
  await File(
    p.join(templateDir.path, 'README.md'),
  ).writeAsString('# {{ project_name }}:{{ port }}\n');
}
