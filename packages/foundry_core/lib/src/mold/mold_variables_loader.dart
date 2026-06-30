import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_variables_payload.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

const _moldVariablesSymbol = 'moldVariables';
const _loadTimeout = Duration(seconds: 30);

/// Timeout used while loading mold variables.
///
/// Exposed for testing slow isolate responses.
@visibleForTesting
Duration moldVariablesLoaderTimeout = _loadTimeout;

/// Loads the `moldVariables` [FoundryVariableGroup] from [variablesFile].
///
/// Executes `variables.dart` in a child isolate so mold code cannot mutate the
/// caller's memory. Throws [MoldLoadException] when the file is missing the
/// required symbol or exports a value of the wrong type.
Future<FoundryVariableGroup> loadMoldVariableGroup({
  required File variablesFile,
}) async {
  if (!variablesFile.existsSync()) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: variablesFile.path,
        message: 'Missing required file "variables.dart".',
      ),
    ]);
  }

  final packageConfigPath = _findPackageConfigPath();
  final wrapper = await _createWrapperScript(
    variablesUri: variablesFile.absolute.uri,
  );

  try {
    final payload = await _spawnWrapper(
      wrapper: wrapper,
      packageConfigPath: packageConfigPath,
      variablesPath: variablesFile.path,
    );
    return deserializeMoldVariableGroup(payload);
  } finally {
    await wrapper.parent.delete(recursive: true);
  }
}

/// Spawns a generated wrapper script and returns the deserialized payload.
///
/// Exposed to exercise isolate failure modes in unit tests.
@visibleForTesting
Future<Map<String, Object?>> spawnMoldVariablesWrapperForTesting({
  required File wrapper,
  required String packageConfigPath,
  required String variablesPath,
}) {
  return _spawnWrapper(
    wrapper: wrapper,
    packageConfigPath: packageConfigPath,
    variablesPath: variablesPath,
  );
}

Future<Map<String, Object?>> _spawnWrapper({
  required File wrapper,
  required String packageConfigPath,
  required String variablesPath,
}) async {
  final receivePort = ReceivePort();
  final exitPort = ReceivePort();

  try {
    await Isolate.spawnUri(
      wrapper.uri,
      const <String>[],
      receivePort.sendPort,
      onExit: exitPort.sendPort,
      packageConfig: File(packageConfigPath).uri,
    );
  } on Object catch (error) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: variablesPath,
        message: _describeSpawnFailure(error),
      ),
    ]);
  }

  final result = await receivePort.first.timeout(
    moldVariablesLoaderTimeout,
    onTimeout: () {
      throw MoldLoadException([
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: variablesPath,
          message: 'Timed out while loading moldVariables.',
        ),
      ]);
    },
  );

  await exitPort.first;

  if (result is String) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: variablesPath,
        message: result,
      ),
    ]);
  }

  if (result is Map<String, Object?>) {
    return result;
  }

  throw MoldLoadException([
    MoldIssue(
      severity: MoldIssueSeverity.error,
      path: variablesPath,
      message: 'Unexpected response while loading moldVariables.',
    ),
  ]);
}

String _describeSpawnFailure(Object error) {
  final message = error.toString();
  if (message.contains(_moldVariablesSymbol) &&
      (message.contains("isn't defined") ||
          message.contains('not found') ||
          message.contains('Undefined name'))) {
    return 'Missing required top-level symbol "$_moldVariablesSymbol".';
  }

  return 'Failed to load moldVariables: $message';
}

Future<File> _createWrapperScript({
  required Uri variablesUri,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('foundry_mold_loader_');
  final wrapper =
      File(p.join(tempDir.path, 'load_mold_variables_wrapper.dart'));
  await wrapper.writeAsString('''
import 'dart:isolate';

import 'package:foundry_core/foundry_core.dart';

import '$variablesUri' as _foundry_mold_variables;

void main(List<String> args, Object? message) {
  final sendPort = message! as SendPort;
  try {
    final value = _foundry_mold_variables.$_moldVariablesSymbol;
    if (value is! FoundryVariableGroup) {
      sendPort.send(
        '$_moldVariablesSymbol must be a FoundryVariableGroup, '
        'but was \${value.runtimeType}.',
      );
      return;
    }
    sendPort.send(_serializeVariableGroup(value));
  } on Object catch (error) {
    sendPort.send('Failed to read $_moldVariablesSymbol: \$error');
  }
}

Map<String, Object?> _serializeVariableGroup(FoundryVariableGroup group) {
  return {
    'variables': {
      for (final entry in group.variables.entries)
        entry.key: _serializeVariable(entry.value),
    },
  };
}

Map<String, Object?> _serializeVariable(FoundryVariable<dynamic> variable) {
  return switch (variable) {
  FoundryStringVariable(:final label) => {
      'kind': 'string',
      'label': label,
    },
  _ => throw UnsupportedError(
      'Unsupported variable type: \${variable.runtimeType}',
    ),
  };
}
''');
  return wrapper;
}

String _findPackageConfigPath() {
  var current = Directory.current;
  while (true) {
    final config =
        File(p.join(current.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      return config.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Could not locate .dart_tool/package_config.json from ${Directory.current.path}',
  );
}
