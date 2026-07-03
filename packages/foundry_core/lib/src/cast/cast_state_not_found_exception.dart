/// Thrown by `readCastState` when `.foundry/last_cast.json` does not exist.
///
/// Signals that no prior `foundry cast` ran in the current working
/// directory — the trigger for `foundry recast` and `foundry finish` to
/// fail with a clear, actionable error.
final class CastStateNotFoundException implements Exception {
  /// Creates a [CastStateNotFoundException] for the missing file at [path].
  const CastStateNotFoundException(this.path);

  /// Path where `last_cast.json` was expected.
  final String path;

  @override
  String toString() =>
      'No cast state found at "$path". Run `foundry cast` first.';
}
