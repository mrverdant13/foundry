/// Thrown by the read accessors on the cast context (`SnapshotFoundryContext`
/// and `FoundryContext`).
///
/// Raised when a `required*` accessor is called for a missing or null key,
/// or when any accessor finds a value of the wrong runtime type.
final class FoundryContextException implements Exception {
  /// Creates a [FoundryContextException] with a human-readable [message].
  const FoundryContextException(this.message);

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => 'FoundryContextException: $message';
}
