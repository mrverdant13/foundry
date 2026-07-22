import 'dart:io';

import 'package:foundry_core/src/pattern/pattern_ignore.dart';
import 'package:foundry_core/src/pattern/pattern_issue.dart';
import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/pattern_marker.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Structured result of inspecting a pattern directory.
@immutable
final class PatternInspectionReport {
  /// Creates a [PatternInspectionReport].
  const PatternInspectionReport({
    required this.rootPath,
    required this.issues,
    this.name,
    this.hasMarker = false,
    this.ignoreGlobs = const [],
    this.lineDeletions = const [],
    this.fileCount = 0,
    this.topLevelEntries = const [],
    this.ignoredPaths = const [],
  });

  /// Path of the inspected pattern root.
  ///
  /// Absolute when [inspectPattern] successfully resolves a directory.
  /// Otherwise the unresolved input path (missing, non-directory, or early
  /// filesystem errors before directory resolution).
  final String rootPath;

  /// Optional name from [patternMarkerRelativePath], when present and valid.
  final String? name;

  /// Whether [patternMarkerRelativePath] exists under [rootPath].
  final bool hasMarker;

  /// Ignore globs loaded from the marker (empty when absent or invalid).
  final List<String> ignoreGlobs;

  /// Line deletions loaded from the marker (empty when absent or invalid).
  ///
  /// Inspect does not apply these; derive / sync use them when writing
  /// `template/`.
  final List<PatternLineDeletion> lineDeletions;

  /// Number of files under [rootPath] that do not match [ignoreGlobs].
  final int fileCount;

  /// Sorted names of immediate children of [rootPath].
  final List<String> topLevelEntries;

  /// Sorted relative POSIX paths that matched [ignoreGlobs].
  final List<String> ignoredPaths;

  /// Issues discovered while inspecting the pattern.
  final List<PatternIssue> issues;

  /// Whether any issue in [issues] is severity [PatternIssueSeverity.error].
  bool get hasErrors {
    return issues.any((issue) => issue.severity == PatternIssueSeverity.error);
  }

  /// Whether the pattern path could be inspected without blocking errors.
  bool get isValid => !hasErrors;
}

/// Resolves the filesystem entity type for a pattern path.
///
/// Overridable in tests to exercise [FileSystemException] handling that is
/// difficult to trigger reliably across platforms.
@visibleForTesting
FileSystemEntityType Function(String path) resolvePatternEntityType =
    _defaultResolvePatternEntityType;

FileSystemEntityType _defaultResolvePatternEntityType(String path) {
  return FileSystemEntity.typeSync(path, followLinks: false);
}

/// Reads the contents of a pattern marker file.
///
/// Overridable in tests to exercise [FileSystemException] handling that is
/// difficult to trigger reliably across platforms.
@visibleForTesting
String Function(File file) readPatternMarkerFile =
    _defaultReadPatternMarkerFile;

String _defaultReadPatternMarkerFile(File file) {
  return file.readAsStringSync();
}

/// Lists immediate children of a pattern directory.
///
/// Overridable in tests to exercise [FileSystemException] handling that is
/// difficult to trigger reliably across platforms.
@visibleForTesting
List<FileSystemEntity> Function(Directory directory) listPatternTopLevel =
    _defaultListPatternTopLevel;

List<FileSystemEntity> _defaultListPatternTopLevel(Directory directory) {
  return directory.listSync(followLinks: false);
}

/// Lists files under a pattern root recursively.
///
/// Used by [inspectPattern] and mold derive. Prefer this over
/// [listPatternFiles] outside of tests — [listPatternFiles] is an injectable
/// hook for filesystem-failure coverage.
Iterable<File> enumeratePatternFiles(String rootPath) {
  return Glob('**', recursive: true)
      .listSync(root: rootPath, followLinks: false)
      .whereType<File>();
}

/// Lists files under a pattern root recursively.
///
/// Overridable in tests to exercise [FileSystemException] handling that is
/// difficult to trigger reliably across platforms.
@visibleForTesting
Iterable<File> Function(String rootPath) listPatternFiles =
    enumeratePatternFiles;

/// Inspects the pattern directory at [patternPath].
///
/// A pattern is any filesystem directory. When
/// [patternMarkerRelativePath] is present it is parsed for an optional name
/// and ignore globs; missing marker files are allowed.
///
/// Missing paths, non-directory paths, and filesystem errors while reading or
/// listing return a report with structured issues instead of throwing.
Future<PatternInspectionReport> inspectPattern(String patternPath) async {
  final FileSystemEntityType entityType;
  try {
    entityType = resolvePatternEntityType(patternPath);
  } on FileSystemException catch (error) {
    return PatternInspectionReport(
      rootPath: patternPath,
      issues: [
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: patternPath,
          message: 'Could not inspect pattern path: ${error.message}',
        ),
      ],
    );
  }

  if (entityType == FileSystemEntityType.notFound) {
    return PatternInspectionReport(
      rootPath: patternPath,
      issues: [
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: patternPath,
          message: 'Pattern directory does not exist.',
        ),
      ],
    );
  }

  if (entityType != FileSystemEntityType.directory) {
    return PatternInspectionReport(
      rootPath: patternPath,
      issues: [
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: patternPath,
          message: 'Pattern path is not a directory.',
        ),
      ],
    );
  }

  final directory = Directory(patternPath);
  final rootPath = directory.absolute.path;
  final issues = <PatternIssue>[];
  final markerFile = File(p.join(rootPath, patternMarkerRelativePath));
  final hasMarker = markerFile.existsSync();

  var marker = const PatternMarker();
  if (hasMarker) {
    try {
      marker = parsePatternMarker(
        yamlContent: readPatternMarkerFile(markerFile),
        sourcePath: markerFile.path,
      );
    } on PatternMarkerException catch (exception) {
      issues.addAll(exception.issues);
    } on FileSystemException catch (error) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: markerFile.path,
          message: 'Could not read pattern marker: ${error.message}',
        ),
      );
    }
  }

  final ignoreGlobs = List<String>.unmodifiable(marker.ignore);
  final lineDeletions = List<PatternLineDeletion>.unmodifiable(
    marker.lineDeletions,
  );
  final ignoreMatchers = compilePatternIgnoreMatchers(ignoreGlobs);

  final List<String> topLevelEntries;
  try {
    topLevelEntries = listPatternTopLevel(directory)
        .map((entity) => p.basename(entity.path))
        .toList()
      ..sort();
  } on FileSystemException catch (error) {
    return PatternInspectionReport(
      rootPath: rootPath,
      name: marker.name,
      hasMarker: hasMarker,
      ignoreGlobs: ignoreGlobs,
      lineDeletions: lineDeletions,
      issues: [
        ...issues,
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: rootPath,
          message: 'Could not list pattern directory: ${error.message}',
        ),
      ],
    );
  }

  final Iterable<File> files;
  try {
    files = listPatternFiles(rootPath);
  } on FileSystemException catch (error) {
    return PatternInspectionReport(
      rootPath: rootPath,
      name: marker.name,
      hasMarker: hasMarker,
      ignoreGlobs: ignoreGlobs,
      lineDeletions: lineDeletions,
      topLevelEntries: List<String>.unmodifiable(topLevelEntries),
      issues: [
        ...issues,
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: rootPath,
          message: 'Could not enumerate pattern files: ${error.message}',
        ),
      ],
    );
  }

  final ignoredPaths = <String>[];
  var fileCount = 0;

  for (final file in files) {
    final relative = p.relative(file.path, from: rootPath);
    final relativePosix = p.posix.joinAll(p.split(relative));
    if (ignoreMatchers.any((matcher) => matcher.matches(relativePosix))) {
      ignoredPaths.add(relativePosix);
      continue;
    }
    fileCount++;
  }
  ignoredPaths.sort();

  return PatternInspectionReport(
    rootPath: rootPath,
    name: marker.name,
    hasMarker: hasMarker,
    ignoreGlobs: ignoreGlobs,
    lineDeletions: lineDeletions,
    fileCount: fileCount,
    topLevelEntries: List<String>.unmodifiable(topLevelEntries),
    ignoredPaths: List<String>.unmodifiable(ignoredPaths),
    issues: issues,
  );
}
