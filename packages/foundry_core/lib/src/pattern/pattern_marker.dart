import 'package:checked_yaml/checked_yaml.dart';
import 'package:foundry_core/src/pattern/pattern_issue.dart';
import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/pattern_replacement.dart';
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
    this.replacements = const [],
    this.lineDeletions = const [],
  });

  /// Optional human-readable pattern name.
  final String? name;

  /// Glob patterns (POSIX) for paths to exclude from pattern summaries.
  ///
  /// Matched against paths relative to the pattern root. Patterns that start
  /// with `**/` also match at the root (for example `**/*.tmp` matches
  /// `scratch.tmp`).
  final List<String> ignore;

  /// Regex replacements for pattern paths and contents during derive / sync.
  ///
  /// Declared under `replacements` in the marker. Not applied by inspect.
  final List<PatternReplacement> replacements;

  /// Line ranges to drop from specific pattern files during derive / sync.
  ///
  /// Declared under `lineDeletions` in the marker. Not applied by inspect.
  final List<PatternLineDeletion> lineDeletions;
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

  final replacements = _decodeReplacements(
    value: map['replacements'],
    sourcePath: sourcePath,
    issues: issues,
  );

  final lineDeletions = _decodeLineDeletions(
    value: map['lineDeletions'],
    sourcePath: sourcePath,
    issues: issues,
  );

  if (issues.isNotEmpty) {
    throw PatternMarkerException(issues);
  }

  return PatternMarker(
    name: name,
    ignore: ignore,
    replacements: replacements,
    lineDeletions: lineDeletions,
  );
}

List<PatternReplacement> _decodeReplacements({
  required Object? value,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "replacements" must be a list of replacement maps.',
      ),
    );
    return const [];
  }

  final replacements = <PatternReplacement>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    final entryPath = 'replacements[$index]';
    if (entry is! Map) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath" must be a map with "from" and "to".',
        ),
      );
      continue;
    }

    final entryMap = Map<Object?, Object?>.from(entry);
    final fromValue = entryMap['from'];
    final toValue = entryMap['to'];

    if (toValue is! String) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath.to" must be a string.',
        ),
      );
      continue;
    }

    final from = _decodeReplacementFrom(
      value: fromValue,
      entryPath: entryPath,
      sourcePath: sourcePath,
      issues: issues,
    );
    if (from == null) {
      continue;
    }

    replacements.add(PatternReplacement(from: from, to: toValue));
  }

  if (issues.isNotEmpty) {
    return const [];
  }
  return List<PatternReplacement>.unmodifiable(replacements);
}

RegExp? _decodeReplacementFrom({
  required Object? value,
  required String entryPath,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  if (value is String) {
    if (value.isEmpty) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath.from" must be a non-empty string '
              'or a regex object.',
        ),
      );
      return null;
    }
    return _tryCompileRegExp(
      pattern: value,
      entryPath: entryPath,
      sourcePath: sourcePath,
      issues: issues,
    );
  }

  if (value is Map) {
    final fromMap = Map<Object?, Object?>.from(value);
    final patternValue = fromMap['pattern'];
    if (patternValue is! String || patternValue.isEmpty) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath.from.pattern" must be a non-empty '
              'string.',
        ),
      );
      return null;
    }

    final flags = _decodeRegExpFlags(
      map: fromMap,
      entryPath: entryPath,
      sourcePath: sourcePath,
      issues: issues,
    );
    if (flags == null) {
      return null;
    }

    return _tryCompileRegExp(
      pattern: patternValue,
      entryPath: entryPath,
      sourcePath: sourcePath,
      issues: issues,
      dotAll: flags.dotAll,
      multiLine: flags.multiLine,
      unicode: flags.unicode,
      caseSensitive: flags.caseSensitive,
    );
  }

  issues.add(
    PatternIssue(
      severity: PatternIssueSeverity.error,
      path: sourcePath,
      message: 'Field "$entryPath.from" must be a non-empty string or a '
          'regex object with "pattern".',
    ),
  );
  return null;
}

({
  bool dotAll,
  bool multiLine,
  bool unicode,
  bool caseSensitive,
})? _decodeRegExpFlags({
  required Map<Object?, Object?> map,
  required String entryPath,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  final defaults = RegExp('.*');
  final issueCountBefore = issues.length;
  final dotAll = _optionalBoolFlag(
    map: map,
    key: 'dotAll',
    entryPath: entryPath,
    sourcePath: sourcePath,
    issues: issues,
  );
  final multiLine = _optionalBoolFlag(
    map: map,
    key: 'multiLine',
    entryPath: entryPath,
    sourcePath: sourcePath,
    issues: issues,
  );
  final unicode = _optionalBoolFlag(
    map: map,
    key: 'unicode',
    entryPath: entryPath,
    sourcePath: sourcePath,
    issues: issues,
  );
  final caseSensitive = _optionalBoolFlag(
    map: map,
    key: 'caseSensitive',
    entryPath: entryPath,
    sourcePath: sourcePath,
    issues: issues,
  );

  if (issues.length > issueCountBefore) {
    return null;
  }

  return (
    dotAll: dotAll ?? defaults.isDotAll,
    multiLine: multiLine ?? defaults.isMultiLine,
    unicode: unicode ?? defaults.isUnicode,
    caseSensitive: caseSensitive ?? defaults.isCaseSensitive,
  );
}

bool? _optionalBoolFlag({
  required Map<Object?, Object?> map,
  required String key,
  required String entryPath,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! bool) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$entryPath.from.$key" must be a boolean.',
      ),
    );
    return null;
  }
  return value;
}

RegExp? _tryCompileRegExp({
  required String pattern,
  required String entryPath,
  required String sourcePath,
  required List<PatternIssue> issues,
  bool? dotAll,
  bool? multiLine,
  bool? unicode,
  bool? caseSensitive,
}) {
  try {
    final defaults = RegExp('.*');
    return RegExp(
      pattern,
      dotAll: dotAll ?? defaults.isDotAll,
      multiLine: multiLine ?? defaults.isMultiLine,
      unicode: unicode ?? defaults.isUnicode,
      caseSensitive: caseSensitive ?? defaults.isCaseSensitive,
    );
  } on FormatException catch (error) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$entryPath.from" is not a valid regular expression: '
            '${error.message}',
      ),
    );
    return null;
  }
}

List<PatternLineDeletion> _decodeLineDeletions({
  required Object? value,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "lineDeletions" must be a list of deletion maps.',
      ),
    );
    return const [];
  }

  final deletions = <PatternLineDeletion>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    final entryPath = 'lineDeletions[$index]';
    if (entry is! Map) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath" must be a map with "filePath" and '
              '"ranges".',
        ),
      );
      continue;
    }

    final entryMap = Map<Object?, Object?>.from(entry);
    final filePathValue = entryMap['filePath'];
    if (filePathValue is! String || filePathValue.trim().isEmpty) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$entryPath.filePath" must be a non-empty string.',
        ),
      );
      continue;
    }

    final ranges = _decodeLineRanges(
      value: entryMap['ranges'],
      entryPath: entryPath,
      sourcePath: sourcePath,
      issues: issues,
    );
    if (ranges == null) {
      continue;
    }

    deletions.add(
      PatternLineDeletion(
        filePath: filePathValue.trim(),
        ranges: ranges,
      ),
    );
  }

  if (issues.isNotEmpty) {
    return const [];
  }
  return List<PatternLineDeletion>.unmodifiable(deletions);
}

List<PatternLineRange>? _decodeLineRanges({
  required Object? value,
  required String entryPath,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  if (value == null) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$entryPath.ranges" must be a list of range maps.',
      ),
    );
    return null;
  }
  if (value is! List) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$entryPath.ranges" must be a list of range maps.',
      ),
    );
    return null;
  }

  final issueCountBefore = issues.length;
  final ranges = <PatternLineRange>[];
  for (var rangeIndex = 0; rangeIndex < value.length; rangeIndex++) {
    final rangeEntry = value[rangeIndex];
    final rangePath = '$entryPath.ranges[$rangeIndex]';
    if (rangeEntry is! Map) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$rangePath" must be a map with "start" and "end".',
        ),
      );
      continue;
    }

    final rangeMap = Map<Object?, Object?>.from(rangeEntry);
    final start = _decodeNonNegativeInt(
      value: rangeMap['start'],
      fieldPath: '$rangePath.start',
      sourcePath: sourcePath,
      issues: issues,
    );
    final end = _decodeNonNegativeInt(
      value: rangeMap['end'],
      fieldPath: '$rangePath.end',
      sourcePath: sourcePath,
      issues: issues,
    );
    if (start == null || end == null) {
      continue;
    }
    if (start > end) {
      issues.add(
        PatternIssue(
          severity: PatternIssueSeverity.error,
          path: sourcePath,
          message: 'Field "$rangePath" must have start <= end '
              '(got start=$start, end=$end).',
        ),
      );
      continue;
    }

    ranges.add(PatternLineRange(start: start, end: end));
  }

  if (issues.length > issueCountBefore) {
    return null;
  }
  return List<PatternLineRange>.unmodifiable(ranges);
}

int? _decodeNonNegativeInt({
  required Object? value,
  required String fieldPath,
  required String sourcePath,
  required List<PatternIssue> issues,
}) {
  if (value is! int || value < 0) {
    issues.add(
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$fieldPath" must be a non-negative integer.',
      ),
    );
    return null;
  }
  return value;
}

String _describeParseFailure(ParsedYamlException error) {
  final message = error.message.trim();
  if (message.isEmpty) {
    return 'Invalid pattern marker YAML.';
  }
  return message;
}
