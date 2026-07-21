import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldSyncException, syncMoldFromPattern;
import 'package:path/path.dart' as p;

/// {@template foundry_cli.mold_sync_command}
/// `foundry mold sync --pattern=<path> [--force]`
///
/// Refreshes an existing mold's `template/` from a pattern directory while
/// preserving root `pubspec.yaml`, `variables.dart`, `hooks/`, and other
/// non-`template/` author edits. Defaults to the mold in the current
/// directory.
/// {@endtemplate}
class MoldSyncCommand extends Command<int> {
  /// {@macro foundry_cli.mold_sync_command}
  MoldSyncCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser
      ..addOption(
        patternOptionName,
        help: 'The pattern directory to sync the mold template from.',
        mandatory: true,
      )
      ..addFlag(
        forceOptionName,
        negatable: false,
        help: 'Replace template/ wholesale (remove orphans that no longer '
            'exist in the pattern). Author edits outside template/ are still '
            'preserved.',
      );
  }

  /// The option name used to provide the pattern directory path.
  static const String patternOptionName = 'pattern';

  /// The flag name used to replace `template/` wholesale.
  static const String forceOptionName = 'force';

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Sync an existing mold template/ from a pattern directory.';

  @override
  String get invocation =>
      '${runner!.executableName} mold sync --pattern=<path> [--force]';

  /// The logger used to report command output.
  final Logger logger;

  /// The mold directory to sync. Defaults to cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    if (!argResults!.wasParsed(patternOptionName)) {
      usageException('Option $patternOptionName is mandatory.');
    }

    final patternOption = argResults!.option(patternOptionName)!;
    final force = argResults!.flag(forceOptionName);

    final patternPath = p.normalize(
      p.join(workingDirectory.path, patternOption),
    );

    try {
      final mold = await syncMoldFromPattern(
        patternPath: patternPath,
        moldDirectory: workingDirectory,
        force: force,
      );
      logger.info('Synced mold at "${mold.path}".');
      return FoundryExitCode.success.code;
    } on MoldSyncException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }
  }
}
