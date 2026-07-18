import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'publish': FoundryObjectVariable(
      label: 'Publish settings',
      group: FoundryVariableGroup(
        variables: {
          'host': FoundryStringVariable(label: 'Host'),
          'port': FoundryIntVariable(label: 'Port'),
          'secure': FoundryBooleanVariable(label: 'Secure'),
        },
      ),
    ),
  },
);
