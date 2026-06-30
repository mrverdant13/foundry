import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';

/// Deserializes a [FoundryVariableGroup] from an isolate-safe payload map.
FoundryVariableGroup deserializeMoldVariableGroup(
  Map<String, Object?> payload,
) {
  final variablesNode = payload['variables'];
  if (variablesNode is! Map) {
    throw const MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message:
            'Loaded moldVariables payload is missing variable definitions.',
      ),
    ]);
  }

  final variables = <String, FoundryVariable<dynamic>>{};
  for (final entry in variablesNode.entries) {
    final key = entry.key.toString();
    final definition = entry.value;
    if (definition is! Map) {
      throw MoldLoadException([
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: 'variables.dart',
          message: 'Invalid variable definition for "$key".',
        ),
      ]);
    }

    switch (definition['kind']) {
      case 'string':
        final label = definition['label']?.toString();
        if (label == null || label.isEmpty) {
          throw MoldLoadException([
            MoldIssue(
              severity: MoldIssueSeverity.error,
              path: 'variables.dart',
              message: 'String variable "$key" is missing a label.',
            ),
          ]);
        }
        variables[key] = FoundryStringVariable(label: label);
      default:
        throw MoldLoadException([
          MoldIssue(
            severity: MoldIssueSeverity.error,
            path: 'variables.dart',
            message: 'Unsupported variable kind for "$key".',
          ),
        ]);
    }
  }

  return FoundryVariableGroup(variables: variables);
}
