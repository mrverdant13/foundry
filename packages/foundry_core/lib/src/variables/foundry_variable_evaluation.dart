import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:meta/meta.dart';

/// One resolved entry produced by [FoundryVariableGroupEvaluation], pairing a
/// visible variable's key and definition with its resolved value.
@immutable
final class FoundryVariableEvaluationEntry {
  /// Creates a [FoundryVariableEvaluationEntry].
  const FoundryVariableEvaluationEntry({
    required this.key,
    required this.variable,
    required this.value,
  });

  /// The variable's key in `FoundryVariableGroup.variables`.
  final String key;

  /// The variable definition this entry was resolved from.
  final FoundryVariable<dynamic> variable;

  /// The resolved value for [key].
  final Object? value;
}

/// Result of evaluating a `FoundryVariableGroup` against a set of raw values.
///
/// Only **visible** variables are represented — entries skipped by
/// `visibleWhen` are absent from both [resolvedValues] and [entries].
@immutable
final class FoundryVariableGroupEvaluation {
  /// Creates a [FoundryVariableGroupEvaluation].
  const FoundryVariableGroupEvaluation({
    required this.resolvedValues,
    required this.entries,
  });

  /// Resolved values for all visible variables, keyed by variable key.
  final Map<String, Object?> resolvedValues;

  /// One entry per visible variable, in declaration order.
  final List<FoundryVariableEvaluationEntry> entries;
}
