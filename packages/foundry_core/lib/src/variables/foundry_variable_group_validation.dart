import 'package:meta/meta.dart';

/// Result of validating a `FoundryVariableGroupEvaluation`.
///
/// Aggregates per-variable validator errors ([fieldErrors]) and cross-field
/// `groupValidators` errors ([groupErrors]).
@immutable
final class FoundryVariableGroupValidation {
  /// Creates a [FoundryVariableGroupValidation].
  const FoundryVariableGroupValidation({
    required this.fieldErrors,
    required this.groupErrors,
  });

  /// Non-empty validator error messages, keyed by variable key.
  ///
  /// Only variables with at least one error are present.
  final Map<String, List<String>> fieldErrors;

  /// Error messages returned by `FoundryVariableGroup.groupValidators`.
  final List<String> groupErrors;

  /// Whether the evaluation has no field or group errors.
  bool get isValid => fieldErrors.isEmpty && groupErrors.isEmpty;
}
