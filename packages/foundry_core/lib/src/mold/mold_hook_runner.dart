import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

const _entryPointSymbol = 'run';

/// Runs the lifecycle hook at [hookFile] for [phase], mutating [context]
/// with any values the hook sets, merges, or removes.
///
/// Does nothing when [hookFile] is `null` or does not exist — missing hooks
/// are no-ops. Otherwise, spawns the hook as a separate `dart run` process
/// from the mold's root package, invoking its required
/// `Future<void> run(FoundryContext context)` entry point with a context
/// seeded from [context]'s current values. The process working directory is
/// [FoundryContext.outputDirectory] (`context.outputDirectory`), matching the
/// `finish` hook cwd contract.
///
/// Throws [MoldHookException] when the mold package config is missing, the
/// process exits with a non-zero status (including an uncaught
/// `FoundryHookException` from the hook), or the process does not produce a
/// valid output payload.
Future<void> runMoldHook({
  required MoldHookPhase phase,
  required File? hookFile,
  required FoundryContext context,
}) async {
  if (hookFile == null || !hookFile.existsSync()) return;

  final packageConfigPath = moldPackageConfigPath(context.moldDirectory);
  if (!File(packageConfigPath).existsSync()) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookFile.path,
      message: 'Missing package config for the mold package. Run '
          '"dart pub get" before running hooks.',
    );
  }

  final workDir = await Directory.systemTemp.createTemp('foundry_mold_hook_');
  try {
    final wrapper = File(p.join(workDir.path, 'run_mold_hook_wrapper.dart'));
    await wrapper.writeAsString(
      _wrapperSource(hookUri: hookFile.absolute.uri),
    );

    final inputFile = File(p.join(workDir.path, 'hook_input.json'));
    final outputFile = File(p.join(workDir.path, 'hook_output.json'));
    try {
      await inputFile.writeAsString(
        jsonEncode({
          'values': context.entries,
          'moldDirectory': context.moldDirectory.absolute.path,
          'outputDirectory': context.outputDirectory.absolute.path,
        }),
      );
    } catch (error) {
      throw MoldHookException(
        phase: phase,
        hookPath: hookFile.path,
        message: 'Failed to prepare hook input: $error',
      );
    }

    final result = await Process.run(
      'dart',
      [
        'run',
        '--packages=${File(packageConfigPath).absolute.path}',
        wrapper.path,
        inputFile.path,
        outputFile.path,
      ],
      workingDirectory: context.outputDirectory.absolute.path,
    );

    final stdoutText = (result.stdout as String).trim();
    if (stdoutText.isNotEmpty) {
      context.logger.info(stdoutText);
    }

    if (result.exitCode != 0) {
      throw MoldHookException(
        phase: phase,
        hookPath: hookFile.path,
        message: _describeHookFailure(result.stderr as String),
      );
    }

    final decoded = readMoldHookOutcome(
      phase: phase,
      hookPath: hookFile.path,
      outputFile: outputFile,
    );
    context._replaceValues(decoded);
  } finally {
    await workDir.delete(recursive: true);
  }
}

/// Reads and validates the JSON payload a hook process wrote to
/// [outputFile].
///
/// Throws [MoldHookException] when [outputFile] is missing, contains
/// malformed JSON, or decodes to something other than a JSON object.
///
/// Exposed for unit tests covering malformed hook output without spawning a
/// process.
@visibleForTesting
Map<String, Object?> readMoldHookOutcome({
  required MoldHookPhase phase,
  required String hookPath,
  required File outputFile,
}) {
  if (!outputFile.existsSync()) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookPath,
      message: 'Hook process did not produce an output payload.',
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(outputFile.readAsStringSync());
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, Object?>) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookPath,
      message: 'Hook process produced an invalid output payload.',
    );
  }
  return decoded;
}

extension on FoundryContext {
  /// Replaces the current values with [updated], removing keys the hook
  /// dropped and applying its sets/merges.
  void _replaceValues(Map<String, Object?> updated) {
    final removedKeys = entries.keys.toSet()..removeAll(updated.keys);
    // A `forEach(remove)` tear-off here would trigger `cascade_invocations`
    // for the following `merge` call on the same receiver.
    // ignore: prefer_foreach
    for (final key in removedKeys) {
      remove(key);
    }
    merge(updated);
  }
}

String _describeHookFailure(String stderrOutput) {
  final trimmed = stderrOutput.trim();
  if (trimmed.isEmpty) {
    return 'Hook process exited with a non-zero status.';
  }

  if (trimmed.contains(_entryPointSymbol) &&
      (trimmed.contains("isn't defined") ||
          trimmed.contains('not found') ||
          trimmed.contains('Undefined name'))) {
    return 'Missing required top-level function '
        '"Future<void> $_entryPointSymbol(FoundryContext context)".';
  }

  final messageLines = <String>[];
  for (final line in trimmed.split('\n')) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith('#')) break;
    if (trimmedLine.isEmpty || trimmedLine == 'Unhandled exception:') {
      continue;
    }
    messageLines.add(trimmedLine);
  }

  return messageLines.isEmpty ? trimmed : messageLines.join(' ');
}

String _wrapperSource({required Uri hookUri}) {
  return '''
import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

import '$hookUri' as _foundry_mold_hook;

Future<void> main(List<String> args) async {
  final inputFile = File(args[0]);
  final outputFile = File(args[1]);

  final input = jsonDecode(await inputFile.readAsString()) as Map;
  final values = Map<String, Object?>.from(input['values'] as Map);
  final moldDirectory = Directory(input['moldDirectory'] as String);
  final outputDirectory = Directory(input['outputDirectory'] as String);

  final context = FoundryContext(
    values: values,
    logger: Logger(),
    moldDirectory: moldDirectory,
    outputDirectory: outputDirectory,
  );

  await _foundry_mold_hook.$_entryPointSymbol(context);

  await outputFile.writeAsString(jsonEncode(context.entries));
}
''';
}
