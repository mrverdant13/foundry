import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// Runs only the mold's finish hook against [outputPath].
typedef FinishHookRunner = Future<void> Function({
  required Mold mold,
  required String outputPath,
  required Map<String, Object?> values,
});

/// {@template foundry_cli.finish_command}
/// `foundry finish [--no-hooks]`
///
/// Runs the finish hook from the last cast's mold against the stored output
/// directory without re-rendering templates.
/// {@endtemplate}
class FinishCommand extends Command<int> {
  /// {@macro foundry_cli.finish_command}
  FinishCommand({
    required this.logger,
    Directory? workingDirectory,
    CastStateReader? readState,
    FinishHookRunner? runFinishHook,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _readState = readState ?? readCastState,
        _runFinishHook = runFinishHook ?? _defaultFinishHookRunner {
    argParser.addFlag(
      CastCommand.noHooksOptionName,
      negatable: false,
      help: 'Skip the finish hook.',
    );
  }

  /// The logger used to report command output.
  final Logger logger;

  /// The directory cast state paths are resolved against and where
  /// `.foundry/last_cast.json` is read.
  final Directory workingDirectory;

  final CastStateReader _readState;
  final FinishHookRunner _runFinishHook;

  @override
  String get name => 'finish';

  @override
  String get description =>
      'Run the finish hook for the last cast without re-rendering templates.';

  @override
  String get invocation => '${runner!.executableName} finish [--no-hooks]';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Too many arguments: finish takes no positional args.');
    }

    final noHooks = argResults!.flag(CastCommand.noHooksOptionName);

    final state = await readCastStateOrReportError(
      logger: logger,
      workingDirectory: workingDirectory,
      readState: _readState,
    );
    if (state == null) {
      return FoundryExitCode.userError.code;
    }

    if (noHooks) {
      logger.info('Finish skipped (--no-hooks).');
      return FoundryExitCode.success.code;
    }

    final moldPath = p.normalize(
      p.join(workingDirectory.path, state.moldPath),
    );
    final outputPath = p.normalize(
      p.join(workingDirectory.path, state.outputPath),
    );

    final Mold mold;
    try {
      mold = await loadMold(moldPath);
    } on MoldLoadException catch (exception) {
      for (final issue in exception.issues) {
        logger.error('${issue.path}: ${issue.message}');
      }
      return FoundryExitCode.userError.code;
    }

    final finishHook = mold.finishHook;
    if (finishHook == null || !finishHook.existsSync()) {
      logger.error(
        'No finish hook defined for mold "${mold.name}" at '
        '${MoldHooks.finishPath}.',
      );
      return FoundryExitCode.userError.code;
    }

    if (!Directory(outputPath).existsSync()) {
      logger.error(
        'Output directory "${state.outputPath}" does not exist. '
        'Run `foundry cast` or `foundry recast` first.',
      );
      return FoundryExitCode.userError.code;
    }

    try {
      await _runFinishHook(
        mold: mold,
        outputPath: outputPath,
        values: state.vars,
      );
    } on MoldHookException catch (exception) {
      logger.error(exception.toString());
      return FoundryExitCode.userError.code;
    }

    logger.info('✓ Finish completed');
    return FoundryExitCode.success.code;
  }
}

Future<void> _defaultFinishHookRunner({
  required Mold mold,
  required String outputPath,
  required Map<String, Object?> values,
}) async {
  final context = FoundryContext(
    values: values,
    logger: Logger(),
    moldDirectory: mold.directory,
    outputDirectory: Directory(outputPath),
  );

  await runMoldHook(
    phase: MoldHookPhase.finish,
    hookFile: mold.finishHook,
    context: context,
  );
}
