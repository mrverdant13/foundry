import 'package:foundry_core/src/variables/foundry_variable_group_validation.dart';

/// Thrown when resolved cast variables fail field or group validation.
///
/// A user error: the prepare hook (if any) already ran, but the gathered
/// variable values did not satisfy the mold's `variables.dart` validators.
/// This happens before the shape and finish hooks run and before any
/// template rendering. Distinct from `FoundryContextException`, which
/// signals misuse of a context accessor rather than a failed validation
/// rule.
final class CastVariablesInvalidException implements Exception {
  /// Creates a [CastVariablesInvalidException] from a failed [validation].
  const CastVariablesInvalidException(this.validation);

  /// The validation result that failed, with field and group errors.
  final FoundryVariableGroupValidation validation;

  @override
  String toString() {
    final buffer = StringBuffer('Cast variables failed validation:');
    for (final fieldEntry in validation.fieldErrors.entries) {
      for (final error in fieldEntry.value) {
        buffer
          ..writeln()
          ..write('  ${fieldEntry.key}: $error');
      }
    }
    for (final error in validation.groupErrors) {
      buffer
        ..writeln()
        ..write('  $error');
    }
    return buffer.toString();
  }
}
