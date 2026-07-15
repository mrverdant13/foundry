import 'package:foundry_core/foundry_core.dart';

const moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
    'prepared_value': FoundryStringVariable(
      label: 'Prepared value',
      defaultValue: (context) => context.requiredString('seed'),
    ),
  },
);
