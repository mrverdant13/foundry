/// An exception a mold hook throws to intentionally abort the running cast.
///
/// Distinct from `FoundryContextException`, which signals misuse of a
/// `FoundryContext` or `SnapshotFoundryContext` accessor. Any uncaught
/// exception — including [FoundryHookException] — aborts the command;
/// Foundry does not roll back partial artifacts.
final class FoundryHookException implements Exception {
  /// Creates a [FoundryHookException] with a human-readable [message].
  const FoundryHookException(this.message);

  /// Human-readable description of why the hook aborted.
  final String message;

  @override
  String toString() => 'FoundryHookException: $message';
}
