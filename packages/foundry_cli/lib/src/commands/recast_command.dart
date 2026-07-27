import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// {@template foundry_cli.recast_command}
/// `foundry recast [--force] [--no-hooks]`
///
/// Replays the last successful `foundry cast` using paths and variable
/// values from `.foundry/last_cast.json` in the process cwd. Launches a mold
/// cast session so lifecycle hooks run against the live `variables.dart`
/// group; stored vars are the encodable projection from the prior cast.
/// {@endtemplate}
class RecastCommand extends Command<int> {
  /// {@macro foundry_cli.recast_command}
  RecastCommand({
    required this.logger,
    Directory? workingDirectory,
    CastStateReader? readState,
    BatchMoldCastSessionLauncher? launchBatchSession,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _readState = readState ?? readCastState,
        _launchBatchSession = launchBatchSession ?? launchBatchMoldCastSession {
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
  final BatchMoldCastSessionLauncher _launchBatchSession;

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

    final result = await _launchBatchSession(
      moldPath: moldPath,
      outputPath: outputPath,
      varsFileValues: state.vars,
      force: force,
      noHooks: noHooks,
    );

    switch (result) {
      case MoldCastSessionLaunchSuccess(
          :final artifactCount,
          :final vars,
          :final exitCode,
        ):
        await writeCastState(
          CastState(
            moldPath: state.moldPath,
            outputPath: state.outputPath,
            vars: vars,
            timestamp: DateTime.now(),
          ),
          cwd: workingDirectory,
        );
        logger
          ..info('✓ Recast completed')
          ..info('✓ $artifactCount artifacts generated at $outputPath');
        return exitCode;
      case MoldCastSessionLaunchFailure(:final message, :final exitCode):
        logger.error(message);
        return exitCode;
    }
  }
}
