import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// {@template foundry_cli.finish_command}
/// `foundry finish [--no-hooks]`
///
/// Runs the finish hook from the last cast's mold against the stored output
/// directory without re-rendering templates. Launches a finish-only mold cast
/// session so the hook runs in-process against the live mold package; vars are
/// seeded from the encodable projection in `.foundry/last_cast.json`.
/// {@endtemplate}
class FinishCommand extends Command<int> {
  /// {@macro foundry_cli.finish_command}
  FinishCommand({
    required this.logger,
    Directory? workingDirectory,
    CastStateReader? readState,
    BatchMoldCastSessionLauncher? launchBatchSession,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _readState = readState ?? readCastState,
        _launchBatchSession = launchBatchSession ?? launchBatchMoldCastSession {
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
  final BatchMoldCastSessionLauncher _launchBatchSession;

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

    if (!Directory(outputPath).existsSync()) {
      logger.error(
        'Output directory "${state.outputPath}" does not exist. '
        'Run `foundry cast` or `foundry recast` first.',
      );
      return FoundryExitCode.userError.code;
    }

    final result = await _launchBatchSession(
      moldPath: moldPath,
      outputPath: outputPath,
      varsFileValues: state.vars,
      finishOnly: true,
    );

    switch (result) {
      case MoldCastSessionLaunchSuccess(:final exitCode):
        logger.info('✓ Finish completed');
        return exitCode;
      case MoldCastSessionLaunchFailure(:final message, :final exitCode):
        logger.error(message);
        return exitCode;
    }
  }
}
