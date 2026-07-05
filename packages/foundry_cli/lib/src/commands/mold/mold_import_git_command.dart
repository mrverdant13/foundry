import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldImportException, importMoldFromGit;

/// {@template foundry_cli.mold_import_git_command}
/// `foundry mold import git --git-url=<url> [--path=<relative/path>] [--force]`
///
/// Shallow-clones a git repository and copies the mold into `./<name>/`
/// under the current directory, where `<name>` comes from the mold's root
/// `pubspec.yaml`.
/// {@endtemplate}
class MoldImportGitCommand extends Command<int> {
  /// {@macro foundry_cli.mold_import_git_command}
  MoldImportGitCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser
      ..addOption(
        gitUrlOptionName,
        help: 'The URL of the git repository to clone.',
        mandatory: true,
      )
      ..addOption(
        pathOptionName,
        help: "The mold's relative path within the repository, when it "
            'does not live at the repository root.',
      )
      ..addFlag(
        forceOptionName,
        negatable: false,
        help: 'Overwrite the destination directory if it already exists.',
      );
  }

  /// The option name used to provide the git repository URL.
  static const String gitUrlOptionName = 'git-url';

  /// The option name used to provide the mold's relative path within the
  /// repository.
  static const String pathOptionName = 'path';

  /// The flag name used to overwrite an existing destination.
  static const String forceOptionName = 'force';

  @override
  String get name => 'git';

  @override
  String get description =>
      'Clone a git repository and copy the mold into ./<name>/.';

  @override
  String get invocation =>
      '${runner!.executableName} mold import git --git-url=<url> '
      '[--path=<relative/path>] [--force]';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory the mold is imported into. Defaults to the process cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    if (!argResults!.wasParsed(gitUrlOptionName)) {
      usageException('Option $gitUrlOptionName is mandatory.');
    }
    final gitUrl = argResults!.option(gitUrlOptionName)!;
    final path = argResults!.option(pathOptionName);
    final force = argResults!.flag(forceOptionName);

    try {
      final destination = await importMoldFromGit(
        gitUrl: gitUrl,
        path: path,
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
