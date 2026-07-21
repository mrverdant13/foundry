/// Thrown when a mold cannot be synced from a pattern directory.
///
/// Covers invalid pattern paths, targets that are not molds, and filesystem
/// failures while staging or writing the synced `template/` tree.
final class MoldSyncException implements Exception {
  /// Creates a [MoldSyncException].
  const MoldSyncException(this.message);

  /// Human-readable description of why sync failed.
  final String message;

  @override
  String toString() => 'MoldSyncException: $message';
}
