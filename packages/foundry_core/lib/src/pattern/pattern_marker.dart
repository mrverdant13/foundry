import 'package:checked_yaml/checked_yaml.dart';
import 'package:foundry_core/src/pattern/pattern_issue.dart';
import 'package:meta/meta.dart';

/// Relative path of the optional pattern marker from a pattern root.
const String patternMarkerRelativePath = '.foundry/pattern.yaml';

/// Optional on-disk marker describing a Foundry pattern directory.
///
/// Present at [patternMarkerRelativePath] when authors want a name and ignore
/// globs for inspect / derive. Any directory remains a valid pattern without
/// this file.
@immutable
final class PatternMarker {
  /// Creates a [PatternMarker].
  const PatternMarker({
    this.name,
    this.ignore = const [],
  });

  /// Optional human-readable pattern name.
  final String? name;

  /// Glob patterns (POSIX) for paths to exclude from pattern summaries.
  ///
  /// Matched against paths relative to the pattern root. Patterns that start
  /// with `**/` also match at the root (for example `**/*.tmp` matches
  /// `scratch.tmp`).
  final List<String> ignore;
}

/// Parses [yamlContent] as a [PatternMarker].
///
/// Throws [PatternMarkerException] when the YAML is not a map or fields have
/// the wrong types.
PatternMarker parsePatternMarker({
  required String yamlContent,
  required String sourcePath,
}) {
  final Map<Object?, Object?>? rawMap;
  try {
    rawMap = checkedYamlDecode<Map<Object?, Object?>?>(
      yamlContent,
      (map) => map == null ? null : Map<Object?, Object?>.from(map),
      sourceUrl: Uri.file(sourcePath),
      allowNull: true,
    );
  } on ParsedYamlException catch (error) {
    throw PatternMarkerException([
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: _describeParseFailure(error),
      ),
    ]);
  }

  return _decodePatternMarker(
    map: rawMap,
    sourcePath: sourcePath,
  );
}

PatternMarker _decodePatternMarker({
  required Map<Object?, Object?>? map,
  required String sourcePath,
}) {
  if (map == null) {
    return const PatternMarker();
  }

  final issues = <PatternIssue>[];

  final nameValue = map['name'];
  String? name;
  if (nameValue != null) {
    if (nameValue is! String || nameValue.trim().isEmpty) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "name" must be a non-empty string.',
        ),
      );
    } else {
      name = nameValue.trim();
    }
  }

  final ignoreValue = map['ignore'];
  var ignore = const <String>[];
  if (ignoreValue != null) {
    if (ignoreValue is! List) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "ignore" must be a list of glob strings.',
        ),
      );
    } else {
      final globs = <String>[];
      for (final entry in ignoreValue) {
        if (entry is! String || entry.trim().isEmpty) {
          issues.add(
            PatternIssue(
              severity: PatternIssueSeverity.error,
              path: sourcePath,
              message: 'Field "ignore" must contain only non-empty strings.',
            ),
          );
          break;
        }
        globs.add(entry.trim());
      }
      if (issues.isEmpty) {
        ignore = List<String>.unmodifiable(globs);
      }
    }
  }

  if (issues.isNotEmpty) {
    throw PatternMarkerException(issues);
  }

  return PatternMarker(name: name, ignore: ignore);
}

String _describeParseFailure(ParsedYamlException error) {
  final message = error.message.trim();
  if (message.isEmpty) {
    return 'Invalid pattern marker YAML.';
  }
  return message;
}
