import 'package:foundry_cli/src/tui/cast_variable_form.dart';
import 'package:foundry_core/foundry_core.dart' show FoundryVariableGroup;
import 'package:nocterm/nocterm.dart'
    show TerminalBackend, VoidCallback, runApp, shutdownApp;

/// Completes an interactive gather session as if the user pressed Escape.
void cancelGatherCastVariables(
  void Function(Map<String, Object?>? values) finish,
) =>
    finish(null);

/// Binds [finish] to the cancel handler passed to [CastVariableForm].
VoidCallback bindGatherCancel(
  void Function(Map<String, Object?>? values) finish,
) =>
    () => cancelGatherCastVariables(finish);

/// Gathers cast variable values through the Nocterm-based [CastVariableForm].
///
/// Runs the TUI to completion and returns the resolved values once the user
/// confirms the form, or `null` if the user cancels (Escape). This is the
/// production implementation of variable gathering used by `foundry cast`;
/// tests inject a fake in its place (see REQUIREMENTS.md §5.1: "Nocterm-only
/// input").
///
/// [backend] overrides Nocterm's default terminal I/O backend, and
/// [enableHotReload] can disable Nocterm's hot-reload watcher; only tests
/// supply either, to drive the TUI without a real terminal or development
/// tooling.
Future<Map<String, Object?>?> gatherCastVariablesInteractively({
  required FoundryVariableGroup variableGroup,
  required String moldName,
  required String moldDescription,
  TerminalBackend? backend,
  bool enableHotReload = true,
}) async {
  Map<String, Object?>? result;
  void finish(Map<String, Object?>? values) {
    result = values;
    shutdownApp();
  }

  await runApp(
    CastVariableForm(
      variableGroup: variableGroup,
      moldName: moldName,
      moldDescription: moldDescription,
      onSubmit: finish,
      onCancel: bindGatherCancel(finish),
    ),
    backend: backend,
    enableHotReload: enableHotReload,
  );
  return result;
}
