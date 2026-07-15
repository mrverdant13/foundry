import 'dart:convert';
import 'dart:io';

import 'package:foundry_cli/src/tui/gather_cast_variables.dart'
    show foundryE2eVarsEnvironmentKey;
import 'package:path/path.dart' as p;

/// Outcome of invoking the `foundry` CLI as a child process.
class FoundryProcessResult {
  /// Creates a [FoundryProcessResult].
  const FoundryProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Process exit code.
  final int exitCode;

  /// Captured stdout.
  final String stdout;

  /// Captured stderr.
  final String stderr;
}

/// Absolute path to `packages/foundry_cli/bin/foundry.dart`.
String foundryCliScriptPath({String? e2ePackageRoot}) {
  if (e2ePackageRoot != null) {
    return p.normalize(
      p.join(e2ePackageRoot, '..', 'bin', 'foundry.dart'),
    );
  }

  var current = Directory.current;
  while (true) {
    final script = File(p.join(current.path, 'bin', 'foundry.dart'));
    if (script.existsSync()) {
      return p.normalize(script.path);
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Could not locate packages/foundry_cli/bin/foundry.dart from '
    '${Directory.current.path}',
  );
}

/// Encodes [values] for [foundryE2eVarsEnvironmentKey].
String encodeFoundryE2eVars(Map<String, Object?> values) {
  return jsonEncode(values);
}

/// Runs `dart run <foundry.dart> …` from [workingDirectory].
Future<FoundryProcessResult> runFoundry(
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
  Map<String, Object?>? e2eVars,
  String? e2ePackageRoot,
}) async {
  final scriptPath = foundryCliScriptPath(e2ePackageRoot: e2ePackageRoot);
  final env = <String, String>{
    ...Platform.environment,
    if (environment != null) ...environment,
    if (e2eVars != null)
      foundryE2eVarsEnvironmentKey: encodeFoundryE2eVars(e2eVars),
  };

  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', scriptPath, ...args],
    workingDirectory: workingDirectory,
    environment: env,
  );

  return FoundryProcessResult(
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  );
}
