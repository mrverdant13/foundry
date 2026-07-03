/// Thrown when a mold cannot be imported into a destination directory.
///
/// Covers missing sources, destination conflicts without `force`, and
/// transport failures (for example a failed `git clone`).
final class MoldImportException implements Exception {
  /// Creates a [MoldImportException].
  const MoldImportException(this.message);

  /// Human-readable description of why the import failed.
  final String message;

  @override
  String toString() => 'MoldImportException: $message';
}
