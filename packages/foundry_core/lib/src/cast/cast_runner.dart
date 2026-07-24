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

/// Creates the cast output directory and runs the **prepare** hook.
///
/// Returns a [FoundryContext] seeded with [values] and any mutations from
/// prepare. When [noHooks] is `true`, prepare is skipped and the context is
/// returned with [values] only.
///
/// Callers that gather variables after prepare (for example the CLI) should
/// seed gather from [FoundryContext.copyValues], merge gathered values into
/// the returned context, and then call [completeCast] so prepare is not run
/// twice. Prefer [castMold] when the full pipeline should run in one shot with
/// no separate gather step.
Future<FoundryContext> prepareCastContext({
  required Mold mold,
  required String outputPath,
  Map<String, Object?> values = const {},
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

  return context;
}

/// Continues a cast after [prepareCastContext] (or an equivalent prepared
/// context): evaluate/validate variables, shape, render, finish.
///
/// Does **not** run the prepare hook. [context] must already point at the
/// cast `--output` directory (typically from [prepareCastContext]). Merge
/// any gathered variable values into [context] before calling this.
///
/// When [noHooks] is `true`, shape and finish are skipped.
///
/// Throws [CastVariablesInvalidException] when resolved variables fail
/// validation, [MoldHookException] when a hook fails, and
/// [TemplateRenderException] when rendering fails (including destination
/// conflicts without [force]). A failed cast does **not** roll back files
/// already written under [context.outputDirectory] (REQUIREMENTS.md §6.2).
Future<CastOutcome> completeCast({
  required Mold mold,
  required FoundryContext context,
  bool force = false,
  bool noHooks = false,
}) async {
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
    outputDirectory: context.outputDirectory,
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
    outputDirectory: context.outputDirectory,
    writtenFiles: writtenFiles,
    values: context.entries,
  );
}

/// Casts [mold] into an artifact at [outputPath].
///
/// Runs the full cast pipeline in order (see REQUIREMENTS.md §6.1):
///
/// 1. Run the **prepare** hook against a [FoundryContext] seeded with
///    [values] ([prepareCastContext]).
/// 2. Evaluate [mold]'s variable group against the prepared values, then
///    validate the result.
/// 3. Run the **shape** hook.
/// 4. Render `template/` to [outputPath] (`renderTemplate`).
/// 5. Run the **finish** hook.
///
/// This is [prepareCastContext] followed by [completeCast]. Gathering values
/// interactively between those phases is the CLI's responsibility (see
/// REQUIREMENTS.md §5.1 / §5.4).
///
/// [mold] must already be loaded (via `loadMold`) with dependencies
/// resolved, so hook subprocesses can be spawned against its package
/// config. A single [FoundryContext] flows through every phase, so hook
/// mutations are visible to later phases and to [CastOutcome.values].
/// [values] seeds that context before the prepare hook runs.
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
  final context = await prepareCastContext(
    mold: mold,
    outputPath: outputPath,
    values: values,
    noHooks: noHooks,
  );
  return completeCast(
    mold: mold,
    context: context,
    force: force,
    noHooks: noHooks,
  );
}
