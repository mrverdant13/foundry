/// Severity of a mold definition issue.
enum MoldIssueSeverity {
  /// Blocks loading or casting the mold.
  error,

  /// Informational; does not block loading (used by inspect in later phases).
  warning,
}

/// A single issue discovered while parsing or loading a mold.
final class MoldIssue {
  /// Creates a [MoldIssue].
  const MoldIssue({
    required this.severity,
    required this.path,
    required this.message,
  });

  /// How severe this issue is.
  final MoldIssueSeverity severity;

  /// File or directory path related to the issue.
  final String path;

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => '${severity.name} [$path]: $message';
}

/// Thrown when a mold cannot be loaded because of one or more [issues].
final class MoldLoadException implements Exception {
  /// Creates a [MoldLoadException].
  const MoldLoadException(this.issues);

  /// All issues that prevented loading.
  final List<MoldIssue> issues;

  @override
  String toString() {
    final buffer = StringBuffer('Failed to load mold:');
    for (final issue in issues) {
      buffer
        ..writeln()
        ..write('  $issue');
    }
    return buffer.toString();
  }
}
