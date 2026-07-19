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

    variables[key] = _deserializeVariable(
      key: key,
      definition: definition,
    );
  }

  return FoundryVariableGroup(variables: variables);
}

FoundryVariable<dynamic> _deserializeVariable({
  required String key,
  required Map<dynamic, dynamic> definition,
}) {
  switch (definition['kind']) {
    case 'string':
      return FoundryStringVariable(
        label: _requireLabel(key: key, kind: 'String', definition: definition),
      );
    case 'boolean':
      return FoundryBooleanVariable(
        label: _requireLabel(
          key: key,
          kind: 'Boolean',
          definition: definition,
        ),
      );
    case 'int':
      return FoundryIntVariable(
        label: _requireLabel(key: key, kind: 'Int', definition: definition),
      );
    case 'double':
      return FoundryDoubleVariable(
        label: _requireLabel(
          key: key,
          kind: 'Double',
          definition: definition,
        ),
      );
    case 'single-choice':
      return FoundrySingleChoiceVariable<String>(
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
      return FoundryMultipleChoiceVariable<String>(
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
    case 'object':
      return FoundryObjectVariable(
        label: _requireLabel(
          key: key,
          kind: 'Object',
          definition: definition,
        ),
        group: _requireNestedGroup(
          key: key,
          definition: definition,
        ),
      );
    case 'values':
      return FoundryValuesVariable<dynamic>(
        label: _requireLabel(
          key: key,
          kind: 'Values',
          definition: definition,
        ),
        item: _requireItemVariable(
          key: key,
          definition: definition,
        ),
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

FoundryVariableGroup _requireNestedGroup({
  required String key,
  required Map<dynamic, dynamic> definition,
}) {
  final groupNode = definition['group'];
  if (groupNode == null) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: 'Object variable "$key" is missing a nested group.',
      ),
    ]);
  }
  if (groupNode is! Map) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: 'Object variable "$key" has an invalid nested group '
            '(${groupNode.runtimeType}).',
      ),
    ]);
  }

  return deserializeMoldVariableGroup(
    Map<String, Object?>.from(groupNode),
  );
}

FoundryVariable<dynamic> _requireItemVariable({
  required String key,
  required Map<dynamic, dynamic> definition,
}) {
  final itemNode = definition['item'];
  if (itemNode == null) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: 'Values variable "$key" is missing an item schema.',
      ),
    ]);
  }
  if (itemNode is! Map) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'variables.dart',
        message: 'Values variable "$key" has an invalid item schema '
            '(${itemNode.runtimeType}).',
      ),
    ]);
  }

  return _deserializeVariable(
    key: '$key.item',
    definition: itemNode,
  );
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
