import 'package:foundry_core/foundry_core.dart';

const moldVariables = FoundryVariableGroup(
  variables: {
    'use_null_safety': FoundryBooleanVariable(label: 'Use null safety'),
    'port': FoundryIntVariable(label: 'Port'),
    'scale': FoundryDoubleVariable(label: 'Scale'),
  },
);
