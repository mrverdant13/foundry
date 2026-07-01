import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_loader.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Standard template directory name relative to a mold root.
const String moldTemplateDirectoryName = 'template';

/// Structured result of inspecting a mold directory.
///
/// [mold] is `null` when the mold could not be loaded at all (in which case
/// [issues] contains the load failure details); otherwise it holds the
/// successfully loaded [Mold] alongside any additional inspection issues.
@immutable
final class MoldInspectionReport {
  /// Creates a [MoldInspectionReport].
  const MoldInspectionReport({
    required this.issues,
    this.mold,
  });

  /// All issues discovered while loading and inspecting the mold.
  final List<MoldIssue> issues;

  /// The loaded mold, or `null` when loading failed.
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
/// Loads the mold (surfacing any [MoldLoadException] issues as part of the
/// report instead of throwing), then checks for the conventional
/// [moldTemplateDirectoryName] directory, an empty variable group, and the
/// presence of optional lifecycle hook files.
Future<MoldInspectionReport> inspectMold(String moldPath) async {
  final Mold mold;
  try {
    mold = await loadMold(moldPath);
  } on MoldLoadException catch (exception) {
    return MoldInspectionReport(issues: exception.issues);
  }

  final issues = <MoldIssue>[
    ..._checkTemplateDirectory(mold),
    ..._checkVariableGroup(mold),
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

Iterable<MoldIssue> _checkVariableGroup(Mold mold) sync* {
  if (mold.variableGroup.variables.isEmpty) {
    yield MoldIssue(
      severity: MoldIssueSeverity.warning,
      path: p.join(mold.directory.path, 'variables.dart'),
      message: 'moldVariables does not define any variables.',
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
