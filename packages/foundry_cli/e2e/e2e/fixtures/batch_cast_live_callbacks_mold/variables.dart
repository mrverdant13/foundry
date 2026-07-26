import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: const ['app', 'package'],
      displayLabel: (value) => value,
    ),
    'project_name': FoundryStringVariable(
      label: 'Project name',
      validators: [
        (value, context) {
          final name = value;
          if (name == null || name.trim().isEmpty) {
            return 'project_name must not be empty';
          }
          if (name.contains(' ')) {
            return 'project_name must not contain spaces';
          }
          return null;
        },
      ],
    ),
    'package_name': FoundryStringVariable(
      label: 'Package name',
      visibleWhen: (context) =>
          context.requiredString('project_type') == 'package',
      defaultValue: (context) =>
          (context.optionalString('project_name') ?? '').toLowerCase(),
    ),
  },
);
