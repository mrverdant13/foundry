import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:meta/meta.dart';

/// Thrown when hook skip/required selection is invalid for a cast.
///
/// Covers skipping a required phase, and requiring a phase whose
/// `hooks/<phase>.dart` file is absent. Distinct from [MoldHookException],
/// which signals a hook that ran and failed.
@immutable
final class MoldHookSelectionException implements Exception {
  /// Creates a [MoldHookSelectionException].
  const MoldHookSelectionException({
    required this.message,
    this.skippedRequiredPhases = const {},
    this.missingRequiredPhases = const {},
  });

  /// Human-readable description of the selection problem.
  final String message;

  /// Required phases that were also listed in `skipHooks`.
  final Set<MoldHookPhase> skippedRequiredPhases;

  /// Required phases whose hook files are missing on disk.
  final Set<MoldHookPhase> missingRequiredPhases;

  @override
  String toString() => 'MoldHookSelectionException: $message';
}
