import 'dart:io';

import 'package:foundry_core/src/mold/mold_derive_exception.dart';
import 'package:foundry_core/src/mold/mold_scaffold.dart';
import 'package:foundry_core/src/mold/mold_template_from_pattern.dart';
import 'package:foundry_core/src/pattern/pattern_inspector.dart';
import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Inspects a pattern path for derive.
///
/// Overridable in tests to exercise structured invalid-pattern messaging.
@visibleForTesting
Future<PatternInspectionReport> Function(String patternPath)
    inspectPatternForDerive = inspectPattern;

/// Commits a staged derived mold into destination.
///
/// Overridable in tests to exercise [FileSystemException] and
/// [MoldDeriveException] handling around the final write.
@visibleForTesting
Future<void> Function({
  required Directory staging,
  required Directory destination,
}) commitDerivedMoldStaging = _defaultCommitDerivedMoldStaging;

/// Resolves the filesystem entity type for a derive destination path.
///
/// Overridable in tests to exercise delete paths that are difficult to create
/// reliably across platforms (for example pipes and unix domain sockets).
@visibleForTesting
FileSystemEntityType Function(String path) resolveDeriveDestinationType =
    _defaultResolveDeriveDestinationType;

FileSystemEntityType _defaultResolveDeriveDestinationType(String path) {
  return FileSystemEntity.typeSync(path, followLinks: false);
}

Future<void> _defaultCommitDerivedMoldStaging({
  required Directory staging,
  required Directory destination,
}) async {
  await _deleteExistingPath(destination.path);
  await destination.parent.create(recursive: true);
  await _copyDirectoryContents(staging, destination);
}

/// Derives a Foundry mold package at [destination] from the pattern directory
/// at [patternPath].
///
/// Writes:
/// - root `pubspec.yaml` depending on `foundry_core`
/// - stub `variables.dart` with a single `FoundryStringVariable`
/// - empty `hooks/`
/// - `template/` tree copied from non-ignored pattern files, with configured
///   `lineDeletions` applied and Liquid-like text content escaped via
///   `liquidizeTemplateContents`
///
/// **Best-effort limitations**
/// - Binary files (NUL bytes) are copied into `template/` unchanged.
/// - Liquidize wraps entire text files that contain `{{` or `{%` in
///   `{% raw %}…{% endraw %}`; nested or pre-existing raw tags may need hand
///   editing afterward.
/// - Path segments that look like Liquid are left as-is (they become template
///   path expressions on cast).
/// - Marker ignore globs exclude files from `template/`; `.foundry/` is always
///   excluded even when not listed in the marker.
/// - Marker `lineDeletions` drop inclusive line ranges from matching text
///   files before liquidize.
///
/// When [destination] already exists as any filesystem entity (directory,
/// file, or symlink) and [force] is `false`, throws [MoldDeriveException].
/// When [force] is `true`, the existing destination is deleted before the
/// derived mold is written.
///
/// Intermediate staging directories are created under [tempParent] (the system
/// temp directory when omitted) with prefix `foundry_mold_derive_` and are
/// always removed afterward, whether or not derive succeeds.
///
/// Returns the absolute [destination] directory.
Future<Directory> deriveMoldFromPattern({
  required String patternPath,
  required Directory destination,
  String? name,
  bool force = false,
  Directory? tempParent,
}) async {
  final report = await inspectPatternForDerive(patternPath);
  if (!report.isValid) {
    final details = report.issues
        .map((issue) => issue.message)
        .where((message) => message.isNotEmpty)
        .join('; ');
    throw MoldDeriveException(
      details.isEmpty
          ? 'Pattern at "$patternPath" could not be inspected.'
          : 'Pattern at "$patternPath" is invalid: $details',
    );
  }

  final moldName = _resolveMoldName(
    explicitName: name,
    markerName: report.name,
    patternRootPath: report.rootPath,
    destination: destination,
  );
  if (!isValidMoldName(moldName)) {
    throw MoldDeriveException(
      'Mold name "$moldName" is not a valid package name '
      '(use lowercase letters, digits, and underscores; '
      'must not start with a digit).',
    );
  }

  final normalizedDestination = Directory(
    p.normalize(destination.absolute.path),
  );
  final normalizedPattern = p.normalize(report.rootPath);
  if (normalizedDestination.path == normalizedPattern ||
      p.isWithin(normalizedPattern, normalizedDestination.path)) {
    throw MoldDeriveException(
      'Destination "${normalizedDestination.path}" cannot be inside the '
      'pattern directory "$normalizedPattern".',
    );
  }

  if (_pathExists(normalizedDestination.path)) {
    if (!force) {
      throw MoldDeriveException(
        'Destination "${normalizedDestination.path}" already exists. Pass '
        'force to overwrite it.',
      );
    }
  }

  final staging = await (tempParent ?? Directory.systemTemp).createTemp(
    'foundry_mold_derive_',
  );
  try {
    await _writeDerivedMold(
      staging: staging,
      patternRootPath: report.rootPath,
      ignoreGlobs: report.ignoreGlobs,
      lineDeletions: report.lineDeletions,
      moldName: moldName,
    );

    await commitDerivedMoldStaging(
      staging: staging,
      destination: normalizedDestination,
    );
    return normalizedDestination;
  } on MoldDeriveException {
    rethrow;
  } on FileSystemException catch (error) {
    final path = error.path;
    final pathSuffix = (path == null || path.isEmpty) ? '' : ' ($path)';
    throw MoldDeriveException(
      'Failed to derive mold at "${normalizedDestination.path}": '
      '${error.message}$pathSuffix.',
    );
  } finally {
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
  }
}

/// Whether [path] refers to any existing filesystem entity.
///
/// Unlike [Directory.existsSync], this is true for files and symlinks as well
/// as directories (links are not followed).
bool _pathExists(String path) {
  return resolveDeriveDestinationType(path) != FileSystemEntityType.notFound;
}

/// Deletes whatever entity currently occupies [path], if any.
///
/// Directories are removed recursively. Files and symlinks are removed without
/// following the link target. Other non-directory entities (for example pipes)
/// are deleted as files.
Future<void> _deleteExistingPath(String path) async {
  final type = resolveDeriveDestinationType(path);
  switch (type) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.directory:
      await Directory(path).delete(recursive: true);
    case FileSystemEntityType.link:
      await Link(path).delete();
    case FileSystemEntityType.file:
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
      await File(path).delete();
  }
}

String _resolveMoldName({
  required String? explicitName,
  required String? markerName,
  required String patternRootPath,
  required Directory destination,
}) {
  if (explicitName != null && explicitName.trim().isNotEmpty) {
    return explicitName.trim();
  }
  if (markerName != null && markerName.trim().isNotEmpty) {
    return sanitizeMoldName(markerName.trim());
  }
  final fromPattern = defaultMoldNameFromPath(patternRootPath);
  if (fromPattern != 'mold') {
    return fromPattern;
  }
  return defaultMoldNameFromPath(destination.path);
}

Future<void> _writeDerivedMold({
  required Directory staging,
  required String patternRootPath,
  required List<String> ignoreGlobs,
  required List<PatternLineDeletion> lineDeletions,
  required String moldName,
}) async {
  await staging.create(recursive: true);

  final pubspecFile = File(p.join(staging.path, 'pubspec.yaml'));
  await pubspecFile.writeAsString(moldScaffoldPubspecContents(moldName));

  final variablesFile = File(p.join(staging.path, 'variables.dart'));
  await variablesFile.writeAsString(moldScaffoldVariablesContents);

  await Directory(p.join(staging.path, 'hooks')).create();
  await writeLiquidizedTemplateFromPattern(
    templateRoot: Directory(p.join(staging.path, 'template')),
    patternRootPath: patternRootPath,
    ignoreGlobs: ignoreGlobs,
    lineDeletions: lineDeletions,
  );
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
      await entity.copy(p.join(destination.path, basename));
    }
  }
}
