import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'dependents': FoundryValuesVariable<String>(
      label: 'Dependents',
      item: FoundryStringVariable(label: 'Package name'),
    ),
  },
);
