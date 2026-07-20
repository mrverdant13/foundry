import 'package:foundry_core/src/variables/foundry_variable_evaluation.dart';
import 'package:foundry_core/src/variables/foundry_variable_group_validation.dart';
import 'package:meta/meta.dart';

/// Outcome of parsing batch cast inputs (`--vars` / `--vars-file`).
@immutable
sealed class CastVariableInputsParseResult {
  /// Creates a [CastVariableInputsParseResult].
  const CastVariableInputsParseResult();

  /// Whether merge, per-kind parsing, and group validation all succeeded.
  bool get isSuccess;
}

/// Successful parse and validation of batch cast variable inputs.
@immutable
final class CastVariableInputsParseSuccess
    extends CastVariableInputsParseResult {
  /// Creates a [CastVariableInputsParseSuccess].
  const CastVariableInputsParseSuccess({
    required this.rawValues,
    required this.evaluation,
  });

  /// Typed merged inputs after per-kind parsing.
  ///
  /// Suitable for seeding `castMold` (or re-evaluation after a prepare hook).
  final Map<String, Object?> rawValues;

  /// Evaluation of [rawValues] against the variable group (defaults applied).
  final FoundryVariableGroupEvaluation evaluation;

  /// Resolved values after visibility and defaults.
  Map<String, Object?> get resolvedValues => evaluation.resolvedValues;

  @override
  bool get isSuccess => true;
}

/// Failed parse or validation of batch cast variable inputs.
@immutable
final class CastVariableInputsParseFailure
    extends CastVariableInputsParseResult {
  /// Creates a [CastVariableInputsParseFailure].
  const CastVariableInputsParseFailure({
    this.unknownKeys = const [],
    this.parseErrors = const {},
    this.varsFlagError,
    this.validation,
  });

  /// Input keys that are not declared on the variable group.
  ///
  /// Nested unknown keys use dotted paths (for example `publish.extra`).
  final List<String> unknownKeys;

  /// Per-key parse or type errors (offending key → message).
  final Map<String, String> parseErrors;

  /// Malformed `--vars` string not attributable to a single key.
  final String? varsFlagError;

  /// Present when merge/parse succeeded but group validation failed.
  final FoundryVariableGroupValidation? validation;

  /// Whether any unknown-key, parse, flag, or validation error is present.
  bool get hasErrors =>
      unknownKeys.isNotEmpty ||
      parseErrors.isNotEmpty ||
      varsFlagError != null ||
      (validation != null && !validation!.isValid);

  @override
  bool get isSuccess => false;

  @override
  String toString() {
    final buffer = StringBuffer('Cast variable inputs failed:');
    if (varsFlagError != null) {
      buffer
        ..writeln()
        ..write('  $varsFlagError');
    }
    for (final key in unknownKeys) {
      buffer
        ..writeln()
        ..write('  Unknown variable "$key".');
    }
    for (final entry in parseErrors.entries) {
      buffer
        ..writeln()
        ..write('  ${entry.key}: ${entry.value}');
    }
    final failedValidation = validation;
    if (failedValidation != null && !failedValidation.isValid) {
      for (final fieldEntry in failedValidation.fieldErrors.entries) {
        for (final error in fieldEntry.value) {
          buffer
            ..writeln()
            ..write('  ${fieldEntry.key}: $error');
        }
      }
      for (final error in failedValidation.groupErrors) {
        buffer
          ..writeln()
          ..write('  $error');
      }
    }
    return buffer.toString();
  }
}
