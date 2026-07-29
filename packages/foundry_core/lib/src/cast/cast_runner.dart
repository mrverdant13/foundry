import 'dart:io';

import 'package:foundry_core/src/cast/cast_hooks.dart';
import 'package:foundry_core/src/cast/cast_outcome.dart';
import 'package:foundry_core/src/cast/cast_variables_invalid_exception.dart';
import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/logging/logger.dart';
import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:foundry_core/src/mold/mold_hook_in_process_runner.dart';
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
///
/// When [hooks] supplies a prepare `MoldHookEntryPoint`, prepare runs
/// in-process on the returned [FoundryContext] (no JSON round-trip).
/// Otherwise `runMoldHook` spawns the hook as a subprocess.
///
/// Throws [MoldHookException] when the prepare hook fails. On failure, the
/// newly created [outputPath] directory (and any files the hook wrote before
/// failing) are left on disk — this call is not a no-op with respect to the
/// filesystem.
Future<FoundryContext> prepareCastContext({
  required Mold mold,
  required String outputPath,
  Map<String, Object?> values = const {},
  bool noHooks = false,
  CastHooks hooks = const CastHooks(),
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
    await _runCastPhaseHook(
      phase: MoldHookPhase.prepare,
      hookFile: mold.prepareHook,
      context: context,
      entryPoint: hooks.prepare,
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
/// [dirtyKeys] are forwarded to variable evaluation so explicitly cleared
/// (null) fields are not replaced by `defaultValue` during this re-evaluate
/// pass. Defaults to empty, matching historical `castMold` behavior.
///
/// When [noHooks] is `true`, shape and finish are skipped. Per-phase
/// [hooks] entry points select in-process vs subprocess execution the same
/// way as [prepareCastContext].
///
/// Throws [CastVariablesInvalidException] when resolved variables fail
/// validation, [MoldHookException] when a hook fails, and
/// [TemplateRenderException] when rendering fails (including destination
/// conflicts without [force]). A failed cast does **not** roll back files
/// already written under `context.outputDirectory`.
Future<CastOutcome> completeCast({
  required Mold mold,
  required FoundryContext context,
  bool force = false,
  bool noHooks = false,
  Set<String> dirtyKeys = const {},
  CastHooks hooks = const CastHooks(),
}) async {
  final evaluation = mold.variableGroup.evaluate(
    rawValues: context.entries,
    dirtyKeys: dirtyKeys,
  );
  final validation = mold.variableGroup.validate(evaluation);
  if (!validation.isValid) {
    throw CastVariablesInvalidException(validation);
  }
  context.merge(evaluation.resolvedValues);

  if (!noHooks) {
    await _runCastPhaseHook(
      phase: MoldHookPhase.shape,
      hookFile: mold.shapeHook,
      context: context,
      entryPoint: hooks.shape,
    );
  }

  final writtenFiles = await renderTemplate(
    templateDirectory: Directory(p.join(mold.directory.path, 'template')),
    outputDirectory: context.outputDirectory,
    context: context.snapshot(),
    force: force,
  );

  if (!noHooks) {
    await _runCastPhaseHook(
      phase: MoldHookPhase.finish,
      hookFile: mold.finishHook,
      context: context,
      entryPoint: hooks.finish,
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
/// Runs the full cast pipeline in order:
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
/// interactively between those phases is the CLI's responsibility.
///
/// [mold] must already be constructed with dependencies resolved (for
/// subprocess hooks) and a live in-memory variable group, so callbacks
/// remain available through evaluate/validate. A single [FoundryContext]
/// flows through every phase, so hook mutations are visible to later
/// phases and to [CastOutcome.values]. [values] seeds that context before
/// the prepare hook runs.
///
/// When [hooks] supplies [MoldHookEntryPoint]s, matching phases run
/// in-process (no JSON boundary). Omitted entry points fall back to
/// [runMoldHook] for that phase.
///
/// When [force] is `false` (the default), rendering fails if a destination
/// file already exists. When [noHooks] is `true`, all three hook phases are
/// skipped. [dirtyKeys] and [hooks] are forwarded to [completeCast].
///
/// Throws [CastVariablesInvalidException] when resolved variables fail
/// validation, [MoldHookException] when a hook fails, and
/// [TemplateRenderException] when rendering fails (including destination
/// conflicts without [force]). A failed cast does **not** roll back files
/// already written to [outputPath].
Future<CastOutcome> castMold({
  required Mold mold,
  required String outputPath,
  Map<String, Object?> values = const {},
  bool force = false,
  bool noHooks = false,
  Set<String> dirtyKeys = const {},
  CastHooks hooks = const CastHooks(),
}) async {
  final context = await prepareCastContext(
    mold: mold,
    outputPath: outputPath,
    values: values,
    noHooks: noHooks,
    hooks: hooks,
  );
  return completeCast(
    mold: mold,
    context: context,
    force: force,
    noHooks: noHooks,
    dirtyKeys: dirtyKeys,
    hooks: hooks,
  );
}

Future<void> _runCastPhaseHook({
  required MoldHookPhase phase,
  required File? hookFile,
  required FoundryContext context,
  required MoldHookEntryPoint? entryPoint,
}) {
  if (entryPoint != null) {
    return runMoldHookInProcess(
      phase: phase,
      hookFile: hookFile,
      context: context,
      entryPoint: entryPoint,
    );
  }
  return runMoldHook(
    phase: phase,
    hookFile: hookFile,
    context: context,
  );
}
