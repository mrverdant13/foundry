/// An exception thrown when interacting with a `FoundryContext` or
/// `SnapshotFoundryContext`.
final class FoundryContextException implements Exception {
  /// Creates a [FoundryContextException] with a human-readable [message].
  const FoundryContextException(this.message);

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => 'FoundryContextException: $message';
}
