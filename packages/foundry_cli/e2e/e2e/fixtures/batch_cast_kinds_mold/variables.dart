import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': const FoundryStringVariable(label: 'Project name'),
    'use_null_safety': const FoundryBooleanVariable(label: 'Use null safety'),
    'port': const FoundryIntVariable(label: 'Port'),
    'scale': const FoundryDoubleVariable(label: 'Scale'),
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: const ['app', 'package'],
      displayLabel: (value) => value,
    ),
    'platforms': FoundryMultipleChoiceVariable<String>(
      label: 'Platforms',
      options: const ['android', 'ios', 'web'],
      displayLabel: (value) => value,
    ),
  },
);
