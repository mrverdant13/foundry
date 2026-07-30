import 'dart:async';
import 'dart:io';

import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:foundry_core/src/mold/mold_hook_failure.dart';

/// Top-level mold hook entry point: `Future<void> run(FoundryContext context)`.
typedef MoldHookEntryPoint = FutureOr<void> Function(FoundryContext context);

final RegExp _dartIdentifierPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

/// Builds a Dart `import` directive for [hookFile] using its absolute file URI.
///
/// Cast-session bridges (and tests) use this so root-level `hooks/*.dart`
/// files can be imported without living under `lib/`, matching the import
/// style of the subprocess hook wrapper.
///
/// [asPrefix] must be a valid Dart identifier. Throws [ArgumentError]
/// otherwise so callers get a clear failure instead of invalid generated
/// source.
String moldHookFileUriImport({
  required File hookFile,
  required String asPrefix,
}) {
  if (!_dartIdentifierPattern.hasMatch(asPrefix)) {
    throw ArgumentError.value(
      asPrefix,
      'asPrefix',
      'Must be a valid Dart identifier.',
    );
  }
  return "import '${hookFile.absolute.uri}' as $asPrefix;";
}

/// Runs the lifecycle hook for [phase] in the **current** isolate.
///
/// Does nothing when [hookFile] is `null` or does not exist — missing hooks
/// are no-ops. Callers that skip a phase (via `skipHooks`) should skip
/// invoking this entirely.
///
/// When the hook file exists, [entryPoint] must be that file's top-level
/// `run` function, typically imported via a file URI:
///
/// ```dart
/// import 'file:///…/hooks/shape.dart' as shape_hook;
///
/// await runMoldHookInProcess(
///   phase: MoldHookPhase.shape,
///   hookFile: shapeFile,
///   context: context,
///   entryPoint: shape_hook.run,
/// );
/// ```
///
/// The **process** working directory ([Directory.current]) is temporarily set
/// to [FoundryContext.outputDirectory] for the duration of [entryPoint],
/// matching the subprocess hook runner's cwd contract. That state is
/// process-wide, not isolate-local — callers must not invoke this concurrently
/// in the same process (for example via `Future.wait`), or relative-path I/O
/// in one hook can race against another's `outputDirectory`.
///
/// Mutations [entryPoint] makes on [context] (including non-JSON `Object`
/// values) remain visible to the caller after this future completes — there
/// is no JSON round-trip.
///
/// Throws [MoldHookException] when [entryPoint] is `null` while the hook file
/// exists (missing `run`), or when the hook throws (including
/// `FoundryHookException`).
Future<void> runMoldHookInProcess({
  required MoldHookPhase phase,
  required File? hookFile,
  required FoundryContext context,
  MoldHookEntryPoint? entryPoint,
}) async {
  if (hookFile == null || !hookFile.existsSync()) return;

  if (entryPoint == null) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookFile.path,
      message: 'Missing required top-level function '
          '"Future<void> run(FoundryContext context)".',
    );
  }

  final previousDirectory = Directory.current;
  Directory.current = context.outputDirectory.absolute;
  try {
    await entryPoint(context);
  } on MoldHookException {
    rethrow;
  } catch (error) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookFile.path,
      message: normalizeMoldHookFailureText('$error'),
    );
  } finally {
    Directory.current = previousDirectory;
  }
}
