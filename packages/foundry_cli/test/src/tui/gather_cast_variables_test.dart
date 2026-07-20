import 'package:args/command_runner.dart' show UsageException;
import 'package:foundry_cli/src/tui/gather_cast_variables.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:nocterm/nocterm.dart' show NoctermBinding, StdioBackend;
import 'package:test/test.dart';

import 'gather_cast_variables_test_support.dart';

void main() {
  tearDown(() {
    createDefaultGatherCastBackend = StdioBackend.new;
    NoctermBinding.resetInstance();
  });

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

  test('createDefaultGatherCastBackend returns a StdioBackend', () {
    final backend = createDefaultGatherCastBackend();
    addTearDown(backend.dispose);
    expect(backend, isA<StdioBackend>());
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
    'gatherCastVariablesInteractively submits without requestExit and '
    'disposes the owned default backend',
    () async {
      final backend = FakeTerminalBackend();
      createDefaultGatherCastBackend = () => backend;

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
        enableHotReload: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      backend.sendBytes([0x0D]);

      expect(await future, {'project_name': 'demo_app'});
      // shutdownApp → StdioBackend.requestExit → dart:io exit would kill the
      // CLI before castMold runs. Gather must complete without requestExit.
      expect(backend.requestExitCount, 0);
      expect(backend.disposeCount, 1);

      // Finish already shut the binding down; a second call must not throw.
      shutdownGatherCastVariables();
      expect(backend.requestExitCount, 0);
    },
  );
}
