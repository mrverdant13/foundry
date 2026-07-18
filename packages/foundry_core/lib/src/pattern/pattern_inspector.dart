import 'dart:io';

import 'package:foundry_core/src/pattern/pattern_issue.dart';
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
    this.fileCount = 0,
    this.topLevelEntries = const [],
    this.ignoredPaths = const [],
  });

  /// Absolute path to the inspected pattern root, when it exists.
  ///
  /// For missing paths this is the unresolved input path.
  final String rootPath;

  /// Optional name from [patternMarkerRelativePath], when present and valid.
  final String? name;

  /// Whether [patternMarkerRelativePath] exists under [rootPath].
  final bool hasMarker;

  /// Ignore globs loaded from the marker (empty when absent or invalid).
  final List<String> ignoreGlobs;

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

/// Inspects the pattern directory at [patternPath].
///
/// A pattern is any filesystem directory. When
/// [patternMarkerRelativePath] is present it is parsed for an optional name
/// and ignore globs; missing marker files are allowed.
///
/// Missing or non-directory paths return a report with structured errors
/// instead of throwing.
Future<PatternInspectionReport> inspectPattern(String patternPath) async {
  final FileSystemEntityType entityType;
  try {
    entityType = FileSystemEntity.typeSync(patternPath, followLinks: false);
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
        yamlContent: markerFile.readAsStringSync(),
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
  final compiledIgnores = [
    for (final pattern in ignoreGlobs) Glob(pattern, context: p.posix),
  ];

  final topLevelEntries = directory
      .listSync(followLinks: false)
      .map((entity) => p.basename(entity.path))
      .toList()
    ..sort();

  final ignoredPaths = <String>[];
  var fileCount = 0;

  final files = Glob('**', recursive: true)
      .listSync(root: rootPath, followLinks: false)
      .whereType<File>();

  for (final file in files) {
    final relative = p.relative(file.path, from: rootPath);
    final relativePosix = p.posix.joinAll(p.split(relative));
    if (_isIgnored(relativePosix, compiledIgnores)) {
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
    fileCount: fileCount,
    topLevelEntries: List<String>.unmodifiable(topLevelEntries),
    ignoredPaths: List<String>.unmodifiable(ignoredPaths),
    issues: issues,
  );
}

/// Whether [relativePosix] matches any [globs].
///
/// Patterns that start with `**/` also match at the pattern root without a
/// directory prefix (`**/*.tmp` matches `scratch.tmp`), matching common
/// gitignore-style expectations while still using [Glob] matching.
bool _isIgnored(String relativePosix, List<Glob> globs) {
  for (final glob in globs) {
    if (glob.matches(relativePosix)) {
      return true;
    }
    final pattern = glob.pattern;
    if (pattern.startsWith('**/')) {
      final withoutPrefix = Glob(
        pattern.substring(3),
        context: p.posix,
      );
      if (withoutPrefix.matches(relativePosix)) {
        return true;
      }
    }
  }
  return false;
}
