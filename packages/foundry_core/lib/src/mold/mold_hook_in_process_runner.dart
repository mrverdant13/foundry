import 'dart:async';
import 'dart:io';

import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';

/// Top-level mold hook entry point: `Future<void> run(FoundryContext context)`.
typedef MoldHookEntryPoint = FutureOr<void> Function(FoundryContext context);

/// Builds a Dart `import` directive for [hookFile] using its absolute file URI.
///
/// Cast-session bridges (and tests) use this so root-level `hooks/*.dart`
/// files can be imported without living under `lib/`, matching the import
/// style of the subprocess hook wrapper.
String moldHookFileUriImport({
  required File hookFile,
  required String asPrefix,
}) {
  return "import '${hookFile.absolute.uri}' as $asPrefix;";
}

/// Runs the lifecycle hook for [phase] in the **current** isolate.
///
/// Does nothing when [hookFile] is `null` or does not exist — missing hooks
/// are no-ops. Callers that honor `--no-hooks` should skip invoking this
/// entirely.
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
/// The isolate working directory is temporarily set to
/// [FoundryContext.outputDirectory] for the duration of [entryPoint], matching
/// the subprocess hook runner's cwd contract.
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
    await Future<void>.sync(() => entryPoint(context));
  } on MoldHookException {
    rethrow;
  } catch (error) {
    throw MoldHookException(
      phase: phase,
      hookPath: hookFile.path,
      message: '$error',
    );
  } finally {
    Directory.current = previousDirectory;
  }
}
