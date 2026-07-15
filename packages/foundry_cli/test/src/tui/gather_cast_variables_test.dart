import 'package:args/command_runner.dart' show UsageException;
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
    'gatherCastVariablesInteractively returns values from FOUNDRY_E2E_VARS',
    () async {
      const variableGroup = FoundryVariableGroup(
        variables: {
          'project_name': FoundryStringVariable(label: 'Project name'),
        },
      );

      final values = await gatherCastVariablesInteractively(
        variableGroup: variableGroup,
        moldName: 'demo_app',
        moldDescription: 'A demo mold.',
        environment: {
          foundryE2eVarsEnvironmentKey: '{"project_name":"Ada"}',
        },
      );

      expect(values, {'project_name': 'Ada'});
    },
  );

  test(
    'gatherCastVariablesInteractively throws UsageException for invalid '
    'FOUNDRY_E2E_VARS JSON',
    () async {
      const variableGroup = FoundryVariableGroup(
        variables: {
          'project_name': FoundryStringVariable(label: 'Project name'),
        },
      );

      await expectLater(
        gatherCastVariablesInteractively(
          variableGroup: variableGroup,
          moldName: 'demo_app',
          moldDescription: 'A demo mold.',
          environment: {
            foundryE2eVarsEnvironmentKey: '{not json}',
          },
        ),
        throwsA(
          isA<UsageException>().having(
            (exception) => exception.message,
            'message',
            contains(foundryE2eVarsEnvironmentKey),
          ),
        ),
      );
    },
  );

  test(
    'gatherCastVariablesInteractively throws UsageException when '
    'FOUNDRY_E2E_VARS is not a JSON object',
    () async {
      const variableGroup = FoundryVariableGroup(
        variables: {
          'project_name': FoundryStringVariable(label: 'Project name'),
        },
      );

      await expectLater(
        gatherCastVariablesInteractively(
          variableGroup: variableGroup,
          moldName: 'demo_app',
          moldDescription: 'A demo mold.',
          environment: {
            foundryE2eVarsEnvironmentKey: '[]',
          },
        ),
        throwsA(
          isA<UsageException>().having(
            (exception) => exception.message,
            'message',
            contains('must be a JSON object'),
          ),
        ),
      );
    },
  );

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
