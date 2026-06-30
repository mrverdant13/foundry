import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
import 'package:foundry_core/src/mold/mold_pubspec_parser.dart';
import 'package:foundry_core/src/mold/mold_variables_loader.dart';
import 'package:path/path.dart' as p;

/// Loads a mold directory containing `pubspec.yaml` and `variables.dart`.
///
/// Throws [MoldLoadException] with structured [MoldIssue]s when the directory,
/// pubspec, or variable definition contract is invalid.
Future<Mold> loadMold(String moldPath) async {
  final directory = Directory(moldPath);
  if (!directory.existsSync()) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: moldPath,
        message: 'Mold directory does not exist.',
      ),
    ]);
  }

  final resolvedDirectory = directory.absolute;
  final pubspecFile = File(p.join(resolvedDirectory.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: pubspecFile.path,
        message: 'Missing required file "pubspec.yaml".',
      ),
    ]);
  }

  final pubspec = parseMoldPubspec(
    yamlContent: await pubspecFile.readAsString(),
    sourcePath: pubspecFile.path,
  );

  await ensureMoldDependencies(resolvedDirectory);

  final variablesFile = File(p.join(resolvedDirectory.path, 'variables.dart'));
  final variableGroup = await loadMoldVariableGroup(
    variablesFile: variablesFile,
    packageConfigPath: moldPackageConfigPath(resolvedDirectory),
  );

  return Mold(
    directory: resolvedDirectory,
    pubspec: pubspec,
    variableGroup: variableGroup,
  );
}
