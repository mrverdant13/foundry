import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pubspec.dart';
import 'package:foundry_core/src/mold/mold_pubspec_parser.dart';
import 'package:foundry_core/src/mold/mold_sync_exception.dart';
import 'package:foundry_core/src/mold/mold_template_from_pattern.dart';
import 'package:foundry_core/src/pattern/pattern_inspector.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_template_relative_path.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Inspects a pattern path for sync.
///
/// Overridable in tests to exercise structured invalid-pattern messaging.
@visibleForTesting
Future<PatternInspectionReport> Function(String patternPath)
    inspectPatternForSync = inspectPattern;

/// Parses a mold `pubspec.yaml` during sync validation.
///
/// Overridable in tests to exercise empty-issue messaging.
@visibleForTesting
MoldPubspec Function({
  required String yamlContent,
  required String sourcePath,
}) parseMoldPubspecForSync = parseMoldPubspec;

/// Commits a staged `template/` tree into an existing mold.
///
/// Overridable in tests to exercise [FileSystemException] and
/// [MoldSyncException] handling around the final write.
@visibleForTesting
Future<void> Function({
  required Directory stagedTemplate,
  required Directory moldDirectory,
  required bool force,
}) commitSyncedMoldTemplate = _defaultCommitSyncedMoldTemplate;

/// Syncs an existing mold at [moldDirectory] from the pattern at [patternPath].
///
/// **Merge rules**
/// - Refreshes files under `template/` from non-ignored pattern files, using
///   the same line-deletion / liquidize / replacement / remotion / binary-copy
///   rules as mold derive.
/// - Marker ignore globs exclude files from `template/`; `.foundry/` is always
///   excluded even when not listed in the marker.
/// - Marker `lineDeletions` drop inclusive line ranges from matching text
///   files before liquidize.
/// - Marker `replacements` rename template-relative paths and rewrite contents
///   after liquidize so injected Liquid stays live.
/// - Remotion annotations (`drop`, `remove-start` / `remove-end`) run after
///   replacements.
/// - Overlapping `template/` paths are overwritten with freshly generated
///   content.
/// - Root `pubspec.yaml`, root `variables.dart`, `hooks/`, and any other
///   non-`template/` mold files are left unchanged.
/// - When [force] is `false`, orphan `template/` files that no longer exist in
///   the pattern are preserved.
/// - When [force] is `true`, the existing `template/` directory is replaced
///   wholesale so removed pattern files disappear from the mold. Author edits
///   outside `template/` are still preserved.
///
/// Throws [MoldSyncException] when [patternPath] is invalid, [moldDirectory]
/// is not an existing mold (missing / unreadable `pubspec.yaml`, invalid mold
/// pubspec, or missing `variables.dart`), the mold path lies inside the
/// pattern, or a filesystem failure occurs while writing.
///
/// Intermediate staging directories are created under [tempParent] (the system
/// temp directory when omitted) with prefix `foundry_mold_sync_` and are
/// always removed afterward, whether or not sync succeeds.
///
/// Returns the absolute [moldDirectory].
Future<Directory> syncMoldFromPattern({
  required String patternPath,
  required Directory moldDirectory,
  bool force = false,
  Directory? tempParent,
}) async {
  final report = await inspectPatternForSync(patternPath);
  if (!report.isValid) {
    final details = report.issues
        .map((issue) => issue.message)
        .where((message) => message.isNotEmpty)
        .join('; ');
    throw MoldSyncException(
      details.isEmpty
          ? 'Pattern at "$patternPath" could not be inspected.'
          : 'Pattern at "$patternPath" is invalid: $details',
    );
  }

  final normalizedMold = Directory(p.normalize(moldDirectory.absolute.path));
  final normalizedPattern = p.normalize(report.rootPath);
  if (normalizedMold.path == normalizedPattern ||
      p.isWithin(normalizedPattern, normalizedMold.path)) {
    throw MoldSyncException(
      'Mold "${normalizedMold.path}" cannot be inside the pattern directory '
      '"$normalizedPattern".',
    );
  }

  await _ensureExistingMold(normalizedMold);

  final staging = await (tempParent ?? Directory.systemTemp).createTemp(
    'foundry_mold_sync_',
  );
  try {
    final stagedTemplate = Directory(p.join(staging.path, 'template'));
    await writeLiquidizedTemplateFromPattern(
      templateRoot: stagedTemplate,
      patternRootPath: report.rootPath,
      ignoreGlobs: report.ignoreGlobs,
      lineDeletions: report.lineDeletions,
      replacements: report.replacements,
    );

    await commitSyncedMoldTemplate(
      stagedTemplate: stagedTemplate,
      moldDirectory: normalizedMold,
      force: force,
    );
    return normalizedMold;
  } on MoldSyncException {
    rethrow;
  } on TemplatePathReplacementException catch (error) {
    throw MoldSyncException(error.message);
  } on FileSystemException catch (error) {
    final path = error.path;
    final pathSuffix = (path == null || path.isEmpty) ? '' : ' ($path)';
    throw MoldSyncException(
      'Failed to sync mold at "${normalizedMold.path}": '
      '${error.message}$pathSuffix.',
    );
  } finally {
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
  }
}

Future<void> _ensureExistingMold(Directory moldDirectory) async {
  if (!moldDirectory.existsSync()) {
    throw MoldSyncException(
      'Mold directory "${moldDirectory.path}" does not exist.',
    );
  }

  final type = FileSystemEntity.typeSync(
    moldDirectory.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.directory) {
    throw MoldSyncException(
      'Mold path "${moldDirectory.path}" is not a directory.',
    );
  }

  final pubspecFile = File(p.join(moldDirectory.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw MoldSyncException(
      'Path "${moldDirectory.path}" is not a mold: missing required file '
      '"pubspec.yaml".',
    );
  }

  try {
    parseMoldPubspecForSync(
      yamlContent: await pubspecFile.readAsString(),
      sourcePath: pubspecFile.path,
    );
  } on MoldLoadException catch (exception) {
    final details = exception.issues
        .map((issue) => issue.message)
        .where((message) => message.isNotEmpty)
        .join('; ');
    throw MoldSyncException(
      details.isEmpty
          ? 'Path "${moldDirectory.path}" is not a mold: invalid pubspec.yaml.'
          : 'Path "${moldDirectory.path}" is not a mold: $details',
    );
  }

  final variablesFile = File(p.join(moldDirectory.path, 'variables.dart'));
  if (!variablesFile.existsSync()) {
    throw MoldSyncException(
      'Path "${moldDirectory.path}" is not a mold: missing required file '
      '"variables.dart".',
    );
  }
}

Future<void> _defaultCommitSyncedMoldTemplate({
  required Directory stagedTemplate,
  required Directory moldDirectory,
  required bool force,
}) async {
  final templateRoot = Directory(p.join(moldDirectory.path, 'template'));
  if (force) {
    if (templateRoot.existsSync()) {
      await templateRoot.delete(recursive: true);
    }
    await _copyDirectoryContents(stagedTemplate, templateRoot);
    return;
  }

  await _copyDirectoryContents(stagedTemplate, templateRoot);
}

Future<void> _copyDirectoryContents(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final basename = p.basename(entity.path);
    if (entity is Directory) {
      await _copyDirectoryContents(
        entity,
        Directory(p.join(destination.path, basename)),
      );
    } else if (entity is File) {
      final destPath = p.join(destination.path, basename);
      final destFile = File(destPath);
      if (destFile.existsSync()) {
        await destFile.delete();
      }
      await entity.copy(destPath);
    }
  }
}
