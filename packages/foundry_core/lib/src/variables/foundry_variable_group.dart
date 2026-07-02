import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_evaluation.dart';
import 'package:meta/meta.dart';

/// Code-first variable schema exported from a mold's variables definition file.
@immutable
final class FoundryVariableGroup {
  /// Creates a [FoundryVariableGroup].
  const FoundryVariableGroup({
    required this.variables,
  });

  /// Variable definitions keyed by context field name.
  final Map<String, FoundryVariable<dynamic>> variables;

  /// Evaluates every variable against [rawValues] in declaration order.
  ///
  /// For each variable, in order:
  ///
  /// 1. Visibility is checked against a [SnapshotFoundryContext] built from
  ///    the values resolved so far merged with [rawValues]; variables whose
  ///    `visibleWhen` returns `false` are skipped entirely — absent from both
  ///    [FoundryVariableGroupEvaluation.resolvedValues] and
  ///    [FoundryVariableGroupEvaluation.entries].
  /// 2. The value is resolved via `FoundryVariable.resolveValue`, which
  ///    preserves a manually supplied or [dirtyKeys] value over a derived
  ///    default.
  ///
  /// Resolved values accumulate as evaluation proceeds, so later variables'
  /// `visibleWhen` and `defaultValue` callbacks can read earlier ones.
  FoundryVariableGroupEvaluation evaluate({
    Map<String, Object?> rawValues = const {},
    Set<String> dirtyKeys = const {},
  }) {
    final resolvedValues = <String, Object?>{};
    final entries = <FoundryVariableEvaluationEntry>[];

    for (final variableEntry in variables.entries) {
      final key = variableEntry.key;
      final variable = variableEntry.value;

      final visibilityContext = SnapshotFoundryContext({
        ...resolvedValues,
        ...rawValues,
      });
      if (!variable.isVisible(visibilityContext)) continue;

      final value = variable.resolveValue(
        key: key,
        rawValues: rawValues,
        dirtyKeys: dirtyKeys,
        resolvedValues: resolvedValues,
      );

      resolvedValues[key] = value;
      entries.add(
        FoundryVariableEvaluationEntry(
          key: key,
          variable: variable,
          value: value,
        ),
      );
    }

    return FoundryVariableGroupEvaluation(
      resolvedValues: Map.unmodifiable(resolvedValues),
      entries: List.unmodifiable(entries),
    );
  }
}
