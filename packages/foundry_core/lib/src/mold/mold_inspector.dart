import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pubspec.dart';
import 'package:foundry_core/src/mold/mold_pubspec_parser.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Standard template directory name relative to a mold root.
const String moldTemplateDirectoryName = 'template';

/// Structured result of inspecting a mold directory.
///
/// [mold] is `null` when the mold could not be loaded at all (in which case
/// [issues] contains the load failure details); otherwise it holds a
/// structurally validated [Mold] alongside any additional inspection issues.
///
/// Structural inspection does **not** import or deserialize `variables.dart`,
/// so [Mold.variableGroup] is always empty. Live variable metadata belongs to
/// a mold cast session describe path.
@immutable
final class MoldInspectionReport {
  /// Creates a [MoldInspectionReport].
  const MoldInspectionReport({
    required this.issues,
    this.mold,
  });

  /// All issues discovered while loading and inspecting the mold.
  final List<MoldIssue> issues;

  /// The structurally validated mold, or `null` when loading failed.
  ///
  /// [Mold.variableGroup] is empty; inspect does not deserialize callbacks.
  final Mold? mold;

  /// Whether any issue in [issues] is severity [MoldIssueSeverity.error].
  bool get hasErrors {
    return issues.any((issue) => issue.severity == MoldIssueSeverity.error);
  }

  /// Whether the mold has no blocking issues.
  bool get isValid => !hasErrors;
}

/// Inspects the mold at [moldPath], reporting structural issues.
///
/// Validates the mold directory, `pubspec.yaml`, and presence of
/// `variables.dart`, then checks for the conventional
/// [moldTemplateDirectoryName] directory and optional lifecycle hook files.
///
/// Does not resolve mold dependencies or deserialize variable callbacks —
/// those require a live mold cast session.
Future<MoldInspectionReport> inspectMold(String moldPath) async {
  final directory = Directory(moldPath);
  if (!directory.existsSync()) {
    return MoldInspectionReport(
      issues: [
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: moldPath,
          message: 'Mold directory does not exist.',
        ),
      ],
    );
  }

  final resolvedDirectory = directory.absolute;
  final pubspecFile = File(p.join(resolvedDirectory.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return MoldInspectionReport(
      issues: [
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: pubspecFile.path,
          message: 'Missing required file "pubspec.yaml".',
        ),
      ],
    );
  }

  final MoldPubspec pubspec;
  try {
    pubspec = parseMoldPubspec(
      yamlContent: await pubspecFile.readAsString(),
      sourcePath: pubspecFile.path,
    );
  } on MoldLoadException catch (exception) {
    return MoldInspectionReport(issues: exception.issues);
  }

  final variablesFile = File(p.join(resolvedDirectory.path, 'variables.dart'));
  if (!variablesFile.existsSync()) {
    return MoldInspectionReport(
      issues: [
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: variablesFile.path,
          message: 'Missing required file "variables.dart".',
        ),
      ],
    );
  }

  final mold = Mold(
    directory: resolvedDirectory,
    pubspec: pubspec,
    variableGroup: const FoundryVariableGroup(variables: {}),
  );

  final issues = <MoldIssue>[
    ..._checkTemplateDirectory(mold),
    ..._reportHooks(mold),
  ];

  return MoldInspectionReport(issues: issues, mold: mold);
}

Iterable<MoldIssue> _checkTemplateDirectory(Mold mold) sync* {
  final templateDirectory = Directory(
    p.join(mold.directory.path, moldTemplateDirectoryName),
  );
  if (!templateDirectory.existsSync()) {
    yield MoldIssue(
      severity: MoldIssueSeverity.error,
      path: templateDirectory.path,
      message: 'Missing required directory "$moldTemplateDirectoryName".',
    );
  }
}

Iterable<MoldIssue> _reportHooks(Mold mold) sync* {
  final hooks = {
    MoldHooks.preparePath: mold.prepareHook,
    MoldHooks.shapePath: mold.shapeHook,
    MoldHooks.finishPath: mold.finishHook,
  };
  for (final MapEntry(key: relativePath, value: hookFile) in hooks.entries) {
    if (hookFile != null) {
      yield MoldIssue(
        severity: MoldIssueSeverity.warning,
        path: hookFile.path,
        message: 'Optional hook "$relativePath" is present.',
      );
    }
  }
}
