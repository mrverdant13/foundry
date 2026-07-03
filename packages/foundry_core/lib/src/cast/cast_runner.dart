import 'dart:io';

import 'package:foundry_core/src/cast/cast_outcome.dart';
import 'package:foundry_core/src/cast/cast_variables_invalid_exception.dart';
import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/logging/logger.dart';
import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:foundry_core/src/mold/mold_hook_runner.dart';
import 'package:foundry_core/src/rendering/template_render_exception.dart';
import 'package:foundry_core/src/rendering/template_renderer.dart';
import 'package:path/path.dart' as p;

/// Casts [mold] into an artifact at [outputPath].
///
/// Runs the full cast pipeline in order (see REQUIREMENTS.md §6.1):
///
/// 1. Run the **prepare** hook against a [FoundryContext] seeded with
///    [values].
/// 2. Evaluate [mold]'s variable group against the prepared values, then
///    validate the result.
/// 3. Run the **shape** hook.
/// 4. Render `template/` to [outputPath] (`renderTemplate`).
/// 5. Run the **finish** hook.
///
/// [mold] must already be loaded (via `loadMold`) with dependencies
/// resolved, so hook subprocesses can be spawned against its package
/// config. A single [FoundryContext] flows through every phase, so hook
/// mutations are visible to later phases and to [CastOutcome.values].
/// [values] seeds that context before the prepare hook runs — this pipeline
/// does not prompt for input; gathering values interactively is the CLI's
/// responsibility (see REQUIREMENTS.md §5.1).
///
/// When [force] is `false` (the default), rendering fails if a destination
/// file already exists. When [noHooks] is `true`, all three hook phases are
/// skipped.
///
/// Throws [CastVariablesInvalidException] when resolved variables fail
/// validation, [MoldHookException] when a hook fails, and
/// [TemplateRenderException] when rendering fails (including destination
/// conflicts without [force]). A failed cast does **not** roll back files
/// already written to [outputPath] (REQUIREMENTS.md §6.2).
Future<CastOutcome> castMold({
  required Mold mold,
  required String outputPath,
  Map<String, Object?> values = const {},
  bool force = false,
  bool noHooks = false,
}) async {
  final outputDirectory = Directory(outputPath);
  await outputDirectory.create(recursive: true);

  final context = FoundryContext(
    values: values,
    logger: Logger(),
    moldDirectory: mold.directory,
    outputDirectory: outputDirectory,
  );

  if (!noHooks) {
    await runMoldHook(
      phase: MoldHookPhase.prepare,
      hookFile: mold.prepareHook,
      context: context,
    );
  }

  final evaluation = mold.variableGroup.evaluate(rawValues: context.entries);
  final validation = mold.variableGroup.validate(evaluation);
  if (!validation.isValid) {
    throw CastVariablesInvalidException(validation);
  }
  context.merge(evaluation.resolvedValues);

  if (!noHooks) {
    await runMoldHook(
      phase: MoldHookPhase.shape,
      hookFile: mold.shapeHook,
      context: context,
    );
  }

  final writtenFiles = await renderTemplate(
    templateDirectory: Directory(p.join(mold.directory.path, 'template')),
    outputDirectory: outputDirectory,
    context: context.snapshot(),
    force: force,
  );

  if (!noHooks) {
    await runMoldHook(
      phase: MoldHookPhase.finish,
      hookFile: mold.finishHook,
      context: context,
    );
  }

  return CastOutcome(
    mold: mold,
    outputDirectory: outputDirectory,
    writtenFiles: writtenFiles,
    values: context.entries,
  );
}
