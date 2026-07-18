/// Severity of a pattern definition or inspection issue.
enum PatternIssueSeverity {
  /// Blocks treating the path as a usable pattern.
  error,

  /// Informational; does not block inspection.
  warning,
}

/// A single issue discovered while inspecting a pattern directory.
final class PatternIssue {
  /// Creates a [PatternIssue].
  const PatternIssue({
    required this.severity,
    required this.path,
    required this.message,
  });

  /// How severe this issue is.
  final PatternIssueSeverity severity;

  /// File or directory path related to the issue.
  final String path;

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => '${severity.name} [$path]: $message';
}

/// Thrown when a pattern marker cannot be parsed.
final class PatternMarkerException implements Exception {
  /// Creates a [PatternMarkerException].
  const PatternMarkerException(this.issues);

  /// All issues that prevented parsing the marker.
  final List<PatternIssue> issues;

  @override
  String toString() {
    final buffer = StringBuffer('Failed to parse pattern marker:');
    for (final issue in issues) {
      buffer
        ..writeln()
        ..write('  $issue');
    }
    return buffer.toString();
  }
}
