import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/src/cast/cast_state.dart';
import 'package:foundry_core/src/cast/cast_state_not_found_exception.dart';
import 'package:path/path.dart' as p;

/// Directory Foundry stores cast state in, relative to the process cwd.
const _stateDirectoryName = '.foundry';

/// File name of the persisted cast state within [_stateDirectoryName].
const _stateFileName = 'last_cast.json';

/// The `.foundry/last_cast.json` file under [cwd] (the process working
/// directory when omitted).
File castStateFile({Directory? cwd}) {
  final base = cwd ?? Directory.current;
  return File(p.join(base.path, _stateDirectoryName, _stateFileName));
}

/// Writes [state] to `.foundry/last_cast.json` under [cwd] (the process
/// working directory when omitted), creating the `.foundry/` directory if it
/// does not already exist. Overwrites any previously persisted state.
Future<void> writeCastState(CastState state, {Directory? cwd}) async {
  final file = castStateFile(cwd: cwd);
  await file.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(state.toJson())}\n');
}

/// Reads and parses `.foundry/last_cast.json` under [cwd] (the process
/// working directory when omitted).
///
/// Throws [CastStateNotFoundException] if no cast state file exists.
Future<CastState> readCastState({Directory? cwd}) async {
  final file = castStateFile(cwd: cwd);
  if (!file.existsSync()) {
    throw CastStateNotFoundException(file.path);
  }
  final contents = await file.readAsString();
  return CastState.fromJson(
    json.decode(contents) as Map<String, Object?>,
  );
}
