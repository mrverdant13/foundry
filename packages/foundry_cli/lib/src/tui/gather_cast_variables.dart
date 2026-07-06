import 'package:foundry_cli/src/tui/cast_variable_form.dart';
import 'package:foundry_core/foundry_core.dart' show FoundryVariableGroup;
import 'package:nocterm/nocterm.dart' show runApp, shutdownApp;

/// Gathers cast variable values through the Nocterm-based [CastVariableForm].
///
/// Runs the TUI to completion and returns the resolved values once the user
/// confirms the form, or `null` if the user cancels (Escape). This is the
/// production implementation of variable gathering used by `foundry cast`;
/// tests inject a fake in its place (see REQUIREMENTS.md §5.1: "Nocterm-only
/// input").
Future<Map<String, Object?>?> gatherCastVariablesInteractively({
  required FoundryVariableGroup variableGroup,
  required String moldName,
  required String moldDescription,
}) async {
  Map<String, Object?>? result;
  await runApp(
    CastVariableForm(
      variableGroup: variableGroup,
      moldName: moldName,
      moldDescription: moldDescription,
      onSubmit: (values) {
        result = values;
        shutdownApp();
      },
      onCancel: () {
        result = null;
        shutdownApp();
      },
    ),
  );
  return result;
}
