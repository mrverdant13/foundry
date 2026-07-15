import 'package:foundry_cli/src/tui/gather_cast_variables.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:nocterm/nocterm.dart' show NoctermBinding;
import 'package:test/test.dart';

import 'gather_cast_variables_test_support.dart';

void main() {
  tearDown(NoctermBinding.resetInstance);

  test('cancelGatherCastVariables completes with null', () {
    Map<String, Object?>? result;
    cancelGatherCastVariables((values) => result = values);
    expect(result, isNull);
  });

  test('bindGatherCancel completes with null', () {
    Map<String, Object?>? result;
    bindGatherCancel((values) => result = values)();
    expect(result, isNull);
  });

  test(
    'gatherCastVariablesInteractively returns the resolved values once the '
    'user submits',
    () async {
      final backend = FakeTerminalBackend();
      final variableGroup = FoundryVariableGroup(
        variables: {
          'project_name': FoundryStringVariable(
            label: 'Project name',
            defaultValue: (context) => 'demo_app',
          ),
        },
      );

      final future = gatherCastVariablesInteractively(
        variableGroup: variableGroup,
        moldName: 'demo_app',
        moldDescription: 'A demo mold.',
        backend: backend,
        enableHotReload: false,
      );

      backend.sendBytes([0x0D]);

      expect(await future, {'project_name': 'demo_app'});
    },
  );
}
