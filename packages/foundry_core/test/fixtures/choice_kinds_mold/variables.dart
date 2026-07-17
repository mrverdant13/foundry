import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
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
