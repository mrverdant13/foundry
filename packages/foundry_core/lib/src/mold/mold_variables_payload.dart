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
        variables[key] = FoundryStringVariable(
          label:
              _requireLabel(key: key, kind: 'String', definition: definition),
        );
      case 'boolean':
        variables[key] = FoundryBooleanVariable(
          label: _requireLabel(
            key: key,
            kind: 'Boolean',
            definition: definition,
          ),
        );
      case 'int':
        variables[key] = FoundryIntVariable(
          label: _requireLabel(key: key, kind: 'Int', definition: definition),
        );
      case 'double':
        variables[key] = FoundryDoubleVariable(
          label: _requireLabel(
            key: key,
            kind: 'Double',
            definition: definition,
          ),
        );
      case 'single-choice':
        variables[key] = FoundrySingleChoiceVariable<String>(
          label: _requireLabel(
            key: key,
            kind: 'SingleChoice',
            definition: definition,
          ),
          options: _requireStringOptions(
            key: key,
            kind: 'SingleChoice',
            definition: definition,
          ),
          displayLabel: _identityDisplayLabel,
        );
      case 'multiple-choice':
        variables[key] = FoundryMultipleChoiceVariable<String>(
          label: _requireLabel(
            key: key,
            kind: 'MultipleChoice',
            definition: definition,
          ),
          options: _requireStringOptions(
            key: key,
            kind: 'MultipleChoice',
            definition: definition,
          ),
          displayLabel: _identityDisplayLabel,
        );
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

String _identityDisplayLabel(String value) => value;

String _requireLabel({
  required String key,
  required String kind,
  required Map<dynamic, dynamic> definition,
}) {
  final label = definition['label']?.toString();
  if (label == null || label.isEmpty) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: '$kind variable "$key" is missing a label.',
      ),
    ]);
  }
  return label;
}

List<String> _requireStringOptions({
  required String key,
  required String kind,
  required Map<dynamic, dynamic> definition,
}) {
  final optionsNode = definition['options'];
  if (optionsNode is! List || optionsNode.isEmpty) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: '$kind variable "$key" is missing string options.',
      ),
    ]);
  }

  final options = <String>[];
  for (final option in optionsNode) {
    if (option is! String || option.isEmpty) {
      throw MoldLoadException([
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: 'variables.dart',
          message: '$kind variable "$key" has a non-string or empty option.',
        ),
      ]);
    }
    options.add(option);
  }
  return options;
}
