import 'package:foundry_core/src/mold/mold_hook_in_process_runner.dart';

/// In-process lifecycle hook entry points for [castMold] / [prepareCastContext] /
/// [completeCast].
///
/// Supply the phase `run` functions when the host already imports mold
/// `hooks/*.dart` (for example via a file URI and [moldHookFileUriImport]).
/// When a hook file exists and the matching entry point is `null`, the cast
/// runner falls back to [runMoldHook] (subprocess + JSON) for that phase.
///
/// Prefer supplying all phases that must share non-JSON context values on the
/// same [FoundryContext] instance. Mixing in-process prepare with subprocess
/// shape drops non-JSON values at the JSON boundary.
final class CastHooks {
  /// Creates hook entry points for prepare, shape, and finish.
  const CastHooks({
    this.prepare,
    this.shape,
    this.finish,
  });

  /// Prepare-phase `run` entry point, or `null` to use subprocess hooks.
  final MoldHookEntryPoint? prepare;

  /// Shape-phase `run` entry point, or `null` to use subprocess hooks.
  final MoldHookEntryPoint? shape;

  /// Finish-phase `run` entry point, or `null` to use subprocess hooks.
  final MoldHookEntryPoint? finish;
}
