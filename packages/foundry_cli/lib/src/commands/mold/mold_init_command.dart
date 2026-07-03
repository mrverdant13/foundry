import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_scaffold.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.mold_init_command}
/// `foundry mold init [--name=<name>]`
///
/// Scaffolds a new mold's root `pubspec.yaml`, `variables.dart`, `template/`,
/// and `hooks/` in the current directory.
/// {@endtemplate}
class MoldInitCommand extends Command<int> {
  /// {@macro foundry_cli.mold_init_command}
  MoldInitCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser.addOption(
      nameOptionName,
      help: 'The mold package name. Defaults to the current directory name.',
    );
  }

  /// The option name used to override the scaffolded mold's package name.
  static const String nameOptionName = 'name';

  @override
  String get name => 'init';

  @override
  String get description =>
      'Scaffold a new mold (pubspec.yaml, variables.dart, template/, '
      'hooks/) in the current directory.';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory the mold is scaffolded into. Defaults to the process cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    final providedName = argResults!.option(nameOptionName);
    final moldName = providedName ?? defaultMoldName(workingDirectory);

    if (!isValidMoldName(moldName)) {
      logger.error(
        'Invalid mold name "$moldName": must contain only lowercase '
        'letters, digits, and underscores, and must not start with a '
        'digit.',
      );
      return FoundryExitCode.userError.code;
    }

    try {
      await scaffoldMold(directory: workingDirectory, name: moldName);
    } on MoldScaffoldException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }

    logger.info(
      'Scaffolded mold "$moldName" in ${workingDirectory.path}',
    );
    return FoundryExitCode.success.code;
  }
}
