import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart' show UsageException;
import 'package:foundry_cli/src/tui/cast_variable_form.dart';
import 'package:foundry_core/foundry_core.dart' show FoundryVariableGroup;
import 'package:nocterm/nocterm.dart'
    show StdioBackend, TerminalBackend, TerminalBinding, VoidCallback, runApp;

/// Environment variable read by [gatherCastVariablesInteractively] during
/// automated e2e tests to supply variable values without a terminal.
const foundryE2eVarsEnvironmentKey = 'FOUNDRY_E2E_VARS';

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

/// Ends the interactive gather TUI and restores the terminal **without**
/// terminating the process.
///
/// Nocterm's `shutdownApp` ends in [TerminalBackend.requestExit]. The default
/// [StdioBackend] implements that via `dart:io` `exit`, which would kill the
/// CLI before `foundry cast` can write `--output`. This helper uses
/// [TerminalBinding.shutdown] so [runApp] can return and casting can continue.
void shutdownGatherCastVariables() {
  final binding = TerminalBinding.instance;
  if (!binding.shouldExit) {
    binding.shutdown();
  }
}

/// Builds the terminal backend used when [gatherCastVariablesInteractively] is
/// not given an explicit backend.
///
/// Defaults to [StdioBackend.new]. Tests may temporarily replace this factory
/// to exercise ownership/dispose without opening a real terminal.
TerminalBackend Function() createDefaultGatherCastBackend = StdioBackend.new;

/// Gathers cast variable values through the Nocterm-based [CastVariableForm].
///
/// Runs the TUI to completion and returns the resolved values once the user
/// confirms the form, or `null` if the user cancels (Escape). This is the
/// production implementation of variable gathering used by interactive
/// `foundry cast` sessions; tests inject a fake in its place.
///
/// [backend] overrides Nocterm's default terminal I/O backend, and
/// [enableHotReload] can disable Nocterm's hot-reload watcher; only tests
/// supply either, to drive the TUI without a real terminal or development
/// tooling.
Future<Map<String, Object?>?> gatherCastVariablesInteractively({
  required FoundryVariableGroup variableGroup,
  required String moldName,
  required String moldDescription,
  Map<String, Object?> seedValues = const {},
  TerminalBackend? backend,
  bool enableHotReload = true,
  Map<String, String>? environment,
}) async {
  final e2eVarsJson =
      (environment ?? Platform.environment)[foundryE2eVarsEnvironmentKey];
  if (e2eVarsJson != null) {
    final Object? decoded;
    try {
      decoded = jsonDecode(e2eVarsJson);
    } on FormatException catch (exception) {
      throw UsageException(
        '$foundryE2eVarsEnvironmentKey must be valid JSON: $exception',
        '',
      );
    }
    if (decoded is! Map) {
      throw UsageException(
        '$foundryE2eVarsEnvironmentKey must be a JSON object.',
        '',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  Map<String, Object?>? result;
  void finish(Map<String, Object?>? values) {
    result = values;
    shutdownGatherCastVariables();
  }

  // Own the default backend so we can dispose signal watchers after the TUI
  // returns; otherwise StdioBackend keeps handling SIGINT and the process may
  // no longer exit on Ctrl+C during the rest of cast.
  final ownsBackend = backend == null;
  final effectiveBackend = backend ?? createDefaultGatherCastBackend();
  try {
    await runApp(
      CastVariableForm(
        variableGroup: variableGroup,
        moldName: moldName,
        moldDescription: moldDescription,
        seedValues: seedValues,
        onSubmit: finish,
        onCancel: bindGatherCancel(finish),
      ),
      backend: effectiveBackend,
      enableHotReload: enableHotReload,
    );
    return result;
  } finally {
    if (ownsBackend) {
      effectiveBackend.dispose();
    }
  }
}
