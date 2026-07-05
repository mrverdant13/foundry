import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldImportException, importMoldFromLocal;

/// {@template foundry_cli.mold_import_local_command}
/// `foundry mold import local --path=<path> [--force]`
///
/// Copies a local mold directory into `./<name>/` under the current
/// directory, where `<name>` comes from the mold's root `pubspec.yaml`.
/// {@endtemplate}
class MoldImportLocalCommand extends Command<int> {
  /// {@macro foundry_cli.mold_import_local_command}
  MoldImportLocalCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser
      ..addOption(
        pathOptionName,
        help: 'The path of the local mold directory to copy.',
        mandatory: true,
      )
      ..addFlag(
        forceOptionName,
        negatable: false,
        help: 'Overwrite the destination directory if it already exists.',
      );
  }

  /// The option name used to provide the local mold source path.
  static const String pathOptionName = 'path';

  /// The flag name used to overwrite an existing destination.
  static const String forceOptionName = 'force';

  @override
  String get name => 'local';

  @override
  String get description => 'Copy a local mold directory into ./<name>/.';

  @override
  String get invocation =>
      '${runner!.executableName} mold import local --path=<path> [--force]';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory the mold is imported into. Defaults to the process cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    if (!argResults!.wasParsed(pathOptionName)) {
      usageException('Option $pathOptionName is mandatory.');
    }
    final sourcePath = argResults!.option(pathOptionName)!;
    final force = argResults!.flag(forceOptionName);

    try {
      final destination = await importMoldFromLocal(
        sourcePath: sourcePath,
        destinationParent: workingDirectory,
        force: force,
      );
      logger.info('Imported mold to "${destination.path}".');
      return FoundryExitCode.success.code;
    } on MoldImportException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }
  }
}
