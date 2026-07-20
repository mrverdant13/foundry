import 'dart:io';

import 'package:foundry_core/foundry_core.dart' show patternMarkerRelativePath;
import 'package:path/path.dart' as p;

/// Thrown when [scaffoldPattern] cannot write the pattern to its target
/// directory.
class PatternScaffoldException implements Exception {
  /// Creates a [PatternScaffoldException] with a user-facing [message].
  const PatternScaffoldException(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() => message;
}

/// Whether [name] is a valid pattern name: non-empty after trimming.
bool isValidPatternName(String name) => name.trim().isNotEmpty;

/// Derives a default pattern name from [directory]'s basename.
///
/// Falls back to `pattern` when the basename is empty (for example a
/// filesystem root).
String defaultPatternName(Directory directory) {
  final basename = p.basename(p.normalize(directory.absolute.path)).trim();
  return basename.isEmpty ? 'pattern' : basename;
}

/// Scaffolds a pattern marker and README stub under [directory].
///
/// Writes [patternMarkerRelativePath] with [name] and starter ignore globs,
/// plus a top-level `README.md`. Throws [PatternScaffoldException] when any
/// scaffold target already exists, to avoid clobbering existing files.
Future<void> scaffoldPattern({
  required Directory directory,
  required String name,
}) async {
  final markerFile = File(p.join(directory.path, patternMarkerRelativePath));
  final readmeFile = File(p.join(directory.path, 'README.md'));
  final foundryDir = Directory(p.join(directory.path, '.foundry'));

  final conflicts = [
    if (markerFile.existsSync()) patternMarkerRelativePath,
    if (readmeFile.existsSync()) 'README.md',
  ];
  if (conflicts.isNotEmpty) {
    throw PatternScaffoldException(
      'A pattern already exists at "${directory.path}" '
      '(${conflicts.join(', ')} already present).',
    );
  }

  try {
    await directory.create(recursive: true);
    await foundryDir.create(recursive: true);
    await markerFile.create(exclusive: true);
    await markerFile.writeAsString(_markerContents(name.trim()));
    await readmeFile.create(exclusive: true);
    await readmeFile.writeAsString(_readmeContents(name.trim()));
  } on FileSystemException catch (exception) {
    throw PatternScaffoldException(
      'Failed to scaffold pattern at "${directory.path}": '
      '${exception.message} (${exception.path}).',
    );
  }
}

String _markerContents(String name) => '''
name: ${_yamlQuotedString(name)}
ignore:
  - .dart_tool/**
  - .git/**
  - build/**
''';

/// Double-quotes [value] so YAML-significant characters in pattern names do
/// not break `.foundry/pattern.yaml`.
String _yamlQuotedString(String value) {
  final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

String _readmeContents(String name) => '''
# $name

This directory is a Foundry **pattern**: a reference project used to inspect
structure and optionally derive or sync a mold.

## Marker

The optional marker at `.foundry/pattern.yaml` names this pattern and lists
ignore globs used when summarizing the pattern tree.

## Next steps

1. Add or adjust the reference files that should seed a mold.
2. Edit `.foundry/pattern.yaml` ignore globs as needed.
3. Review the pattern tree (and ignored paths) before deriving a mold.
''';
