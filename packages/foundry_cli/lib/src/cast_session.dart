import 'dart:io';

import 'package:foundry_cli/src/cast_session_vars.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// In-process lifecycle hook entry points for a [CastSession].
///
/// Callers that import mold `hooks/*.dart` by file URI (or construct closures
/// in tests) supply the phase `run` functions here. Missing entry points are
/// fine when the corresponding hook file is absent; when a hook file exists
/// and [CastSession.runBatch] is not skipping hooks, `runMoldHookInProcess`
/// reports a missing `run` entry point.
final class CastSessionHooks {
  /// Creates hook entry points for prepare, shape, and finish.
  const CastSessionHooks({
    this.prepare,
    this.shape,
    this.finish,
  });

  /// Prepare-phase `run` entry point, or `null` when unused.
  final MoldHookEntryPoint? prepare;

  /// Shape-phase `run` entry point, or `null` when unused.
  final MoldHookEntryPoint? shape;

  /// Finish-phase `run` entry point, or `null` when unused.
  final MoldHookEntryPoint? finish;
}

/// Outcome of [CastSession.runBatch].
sealed class BatchCastSessionResult {
  const BatchCastSessionResult();

  /// Whether the session completed successfully.
  bool get isSuccess;
}

/// Successful batch cast session.
final class BatchCastSessionSuccess extends BatchCastSessionResult {
  /// Creates a successful session result.
  const BatchCastSessionSuccess({
    required this.artifactCount,
    required this.vars,
    required this.writtenFiles,
    required this.outputDirectory,
  });

  /// Number of files rendered into [outputDirectory].
  final int artifactCount;

  /// JSON-encodable variable projection suitable for cast-state persistence.
  final Map<String, Object?> vars;

  /// Files written by template rendering, in template-relative path order.
  final List<File> writtenFiles;

  /// The cast `--output` directory.
  final Directory outputDirectory;

  @override
  bool get isSuccess => true;
}

/// Failed batch cast session.
sealed class BatchCastSessionFailure extends BatchCastSessionResult {
  const BatchCastSessionFailure();

  /// Human-readable failure description for CLI / logging.
  String get message;

  @override
  bool get isSuccess => false;
}

/// Batch inputs failed to parse or validate against the live variable group.
final class BatchCastSessionParseFailure extends BatchCastSessionFailure {
  /// Creates a parse/validation failure.
  const BatchCastSessionParseFailure(this.parseFailure);

  /// Underlying `--vars` / `--vars-file` parse result.
  final CastVariableInputsParseFailure parseFailure;

  @override
  String get message => '$parseFailure';
}

/// A lifecycle hook failed during the session.
final class BatchCastSessionHookFailure extends BatchCastSessionFailure {
  /// Creates a hook failure.
  const BatchCastSessionHookFailure(this.exception);

  /// Underlying in-process hook failure.
  final MoldHookException exception;

  @override
  String get message => exception.toString();
}

/// Template rendering failed during the session.
final class BatchCastSessionRenderFailure extends BatchCastSessionFailure {
  /// Creates a render failure.
  const BatchCastSessionRenderFailure(this.exception);

  /// Underlying template render failure.
  final TemplateRenderException exception;

  @override
  String get message => exception.message;
}

/// Variable evaluation failed with a typed context error.
final class BatchCastSessionContextFailure extends BatchCastSessionFailure {
  /// Creates a context/type failure.
  const BatchCastSessionContextFailure(this.exception);

  /// Underlying context exception.
  final FoundryContextException exception;

  @override
  String get message => 'Invalid cast variable input: ${exception.message}';
}

/// Runs a batch cast against a **live** [Mold.variableGroup] in the current
/// isolate.
///
/// Pipeline: prepare → batch parse/evaluate/validate → shape → render →
/// finish. Hooks use [runMoldHookInProcess] so prepare-seeded non-JSON values
/// remain visible to later phases on the same [FoundryContext] instance.
/// Batch parse marks user-supplied keys dirty so explicit JSON `null` is not
/// overwritten by `defaultValue`; the parse evaluation is reused for shape
/// and render (no second evaluate/validate pass).
///
/// This API does not change host `foundry cast` behavior; callers (session
/// bridges, tests) invoke it directly with an in-memory or same-isolate
/// constructed [Mold].
final class CastSession {
  /// Creates a cast session for [mold] writing into [outputPath].
  const CastSession({
    required this.mold,
    required this.outputPath,
    this.hooks = const CastSessionHooks(),
    this.logger,
  });

  /// Mold whose live [Mold.variableGroup] drives evaluation.
  final Mold mold;

  /// Absolute or relative path of the cast `--output` directory.
  final String outputPath;

  /// In-process hook entry points for prepare / shape / finish.
  final CastSessionHooks hooks;

  /// Logger installed on the session [FoundryContext]; defaults to [Logger].
  final Logger? logger;

  /// Runs the batch pipeline with optional `--vars` / `--vars-file` inputs.
  ///
  /// [varsFileValues] is the decoded JSON object from `--vars-file` (or
  /// `null` when omitted). [varsFlag] is the raw `--vars` string.
  /// When [noHooks] is `true`, prepare / shape / finish are skipped.
  Future<BatchCastSessionResult> runBatch({
    Map<String, Object?>? varsFileValues,
    String? varsFlag,
    bool force = false,
    bool noHooks = false,
  }) async {
    final outputDirectory = Directory(outputPath);
    await outputDirectory.create(recursive: true);

    final context = FoundryContext(
      logger: logger ?? Logger(),
      moldDirectory: mold.directory,
      outputDirectory: outputDirectory,
    );

    if (!noHooks) {
      try {
        await runMoldHookInProcess(
          phase: MoldHookPhase.prepare,
          hookFile: mold.prepareHook,
          context: context,
          entryPoint: hooks.prepare,
        );
      } on MoldHookException catch (exception) {
        return BatchCastSessionHookFailure(exception);
      }
    }

    final CastVariableInputsParseResult parseResult;
    try {
      parseResult = parseCastVariableInputs(
        variableGroup: mold.variableGroup,
        varsFileValues: varsFileValues,
        varsFlag: varsFlag,
        seedValues: context.copyValues(),
      );
    } on FoundryContextException catch (exception) {
      return BatchCastSessionContextFailure(exception);
    }

    switch (parseResult) {
      case CastVariableInputsParseFailure():
        return BatchCastSessionParseFailure(parseResult);
      case CastVariableInputsParseSuccess(:final evaluation):
        // Reuse the parse-time evaluation (already dirtyKeys-aware and
        // validated). Prepare-seeded non-variable keys stay on [context].
        context.merge(evaluation.resolvedValues);
        return _completeBatch(
          context: context,
          force: force,
          noHooks: noHooks,
        );
    }
  }

  Future<BatchCastSessionResult> _completeBatch({
    required FoundryContext context,
    required bool force,
    required bool noHooks,
  }) async {
    if (!noHooks) {
      try {
        await runMoldHookInProcess(
          phase: MoldHookPhase.shape,
          hookFile: mold.shapeHook,
          context: context,
          entryPoint: hooks.shape,
        );
      } on MoldHookException catch (exception) {
        return BatchCastSessionHookFailure(exception);
      }
    }

    final List<File> writtenFiles;
    try {
      writtenFiles = await renderTemplate(
        templateDirectory: Directory(p.join(mold.directory.path, 'template')),
        outputDirectory: context.outputDirectory,
        context: context.snapshot(),
        force: force,
      );
    } on TemplateRenderException catch (exception) {
      return BatchCastSessionRenderFailure(exception);
    }

    if (!noHooks) {
      try {
        await runMoldHookInProcess(
          phase: MoldHookPhase.finish,
          hookFile: mold.finishHook,
          context: context,
          entryPoint: hooks.finish,
        );
      } on MoldHookException catch (exception) {
        return BatchCastSessionHookFailure(exception);
      }
    }

    return BatchCastSessionSuccess(
      artifactCount: writtenFiles.length,
      vars: projectEncodableCastVars(context.copyValues()),
      writtenFiles: writtenFiles,
      outputDirectory: context.outputDirectory,
    );
  }
}
