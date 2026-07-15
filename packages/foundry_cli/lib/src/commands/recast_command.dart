import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// {@template foundry_cli.recast_command}
/// `foundry recast [--force] [--no-hooks]`
///
/// Replays the last successful `foundry cast` using paths and variable
/// values from `.foundry/last_cast.json` in the process cwd.
/// {@endtemplate}
class RecastCommand extends Command<int> {
  /// {@macro foundry_cli.recast_command}
  RecastCommand({
    required this.logger,
    Directory? workingDirectory,
    CastStateReader? readState,
    CastRunner? runCast,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _readState = readState ?? readCastState,
        _runCast = runCast ?? castMold {
    argParser
      ..addFlag(
        CastCommand.forceOptionName,
        negatable: false,
        help: 'Allow casting into a non-empty output directory.',
      )
      ..addFlag(
        CastCommand.noHooksOptionName,
        negatable: false,
        help: 'Skip all lifecycle hooks (prepare, shape, finish).',
      );
  }

  /// The logger used to report command output.
  final Logger logger;

  /// The directory cast state paths are resolved against and where
  /// `.foundry/last_cast.json` is read and updated.
  final Directory workingDirectory;

  final CastStateReader _readState;
  final CastRunner _runCast;

  @override
  String get name => 'recast';

  @override
  String get description =>
      'Replay the last cast using stored paths and variable values.';

  @override
  String get invocation =>
      '${runner!.executableName} recast [--force] [--no-hooks]';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Too many arguments: recast takes no positional args.');
    }

    final force = argResults!.flag(CastCommand.forceOptionName);
    final noHooks = argResults!.flag(CastCommand.noHooksOptionName);

    final state = await readCastStateOrReportError(
      logger: logger,
      workingDirectory: workingDirectory,
      readState: _readState,
    );
    if (state == null) {
      return FoundryExitCode.userError.code;
    }

    final moldPath = p.normalize(
      p.join(workingDirectory.path, state.moldPath),
    );
    final outputPath = p.normalize(
      p.join(workingDirectory.path, state.outputPath),
    );

    final outputDirectory = Directory(outputPath);
    if (!force &&
        outputDirectory.existsSync() &&
        outputDirectory.listSync().isNotEmpty) {
      logger.error(
        'Output directory "${state.outputPath}" already exists and is not '
        'empty. Use --force to recast into it anyway.',
      );
      return FoundryExitCode.userError.code;
    }

    final Mold mold;
    try {
      mold = await loadMold(moldPath);
    } on MoldLoadException catch (exception) {
      for (final issue in exception.issues) {
        logger.error('${issue.path}: ${issue.message}');
      }
      return FoundryExitCode.userError.code;
    }

    final CastOutcome outcome;
    try {
      outcome = await _runCast(
        mold: mold,
        outputPath: outputPath,
        values: state.vars,
        force: force,
        noHooks: noHooks,
      );
    } on CastVariablesInvalidException catch (exception) {
      logger.error('Cast variables are invalid:');
      for (final fieldEntry in exception.validation.fieldErrors.entries) {
        for (final error in fieldEntry.value) {
          logger.error('  ${fieldEntry.key}: $error');
        }
      }
      for (final error in exception.validation.groupErrors) {
        logger.error('  $error');
      }
      return FoundryExitCode.userError.code;
    } on FoundryContextException catch (exception) {
      logger.error('Invalid cast variable input: ${exception.message}');
      return FoundryExitCode.userError.code;
    } on MoldHookException catch (exception) {
      logger.error(exception.toString());
      return FoundryExitCode.userError.code;
    } on TemplateRenderException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }

    await writeCastState(
      CastState(
        moldPath: state.moldPath,
        outputPath: state.outputPath,
        vars: outcome.values,
        timestamp: DateTime.now(),
      ),
      cwd: workingDirectory,
    );

    logger
      ..info('✓ Recast completed')
      ..info('✓ ${outcome.artifactCount} artifacts generated at $outputPath');
    return FoundryExitCode.success.code;
  }
}
