/// Lifecycle phases in which a mold hook may run during a cast.
enum MoldHookPhase {
  /// Runs before variable resolution.
  prepare,

  /// Runs after variables are resolved, before template rendering.
  shape,

  /// Runs after the cast output is written.
  finish,
}

/// Thrown when a mold lifecycle hook process fails to run to completion.
///
/// Covers both process failures (non-zero exit code, malformed output) and
/// any uncaught exception raised by the hook itself, including
/// `FoundryHookException`. Distinct from `FoundryHookException`, which is the
/// type mold authors throw from within a hook to intentionally abort a cast.
final class MoldHookException implements Exception {
  /// Creates a [MoldHookException].
  const MoldHookException({
    required this.phase,
    required this.hookPath,
    required this.message,
  });

  /// Which lifecycle phase the failing hook belongs to.
  final MoldHookPhase phase;

  /// Path to the hook file that failed to run.
  final String hookPath;

  /// Human-readable description of why the hook failed.
  final String message;

  @override
  String toString() => 'MoldHookException(${phase.name}, $hookPath): $message';
}
