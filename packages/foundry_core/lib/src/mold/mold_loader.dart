import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_manifest_parser.dart';
import 'package:foundry_core/src/mold/mold_variables_loader.dart';
import 'package:path/path.dart' as p;

/// Loads a mold directory containing `mold.yaml` and `variables.dart`.
///
/// Throws [MoldLoadException] with structured [MoldIssue]s when the directory,
/// manifest, or variable definition contract is invalid.
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
  final manifestFile = File(p.join(resolvedDirectory.path, 'mold.yaml'));
  if (!manifestFile.existsSync()) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: manifestFile.path,
        message: 'Missing required file "mold.yaml".',
      ),
    ]);
  }

  final manifest = parseMoldManifest(
    yamlContent: await manifestFile.readAsString(),
    sourcePath: manifestFile.path,
  );

  final variablesFile = File(p.join(resolvedDirectory.path, 'variables.dart'));
  final variableGroup =
      await loadMoldVariableGroup(variablesFile: variablesFile);

  return Mold(
    directory: resolvedDirectory,
    manifest: manifest,
    variableGroup: variableGroup,
  );
}
