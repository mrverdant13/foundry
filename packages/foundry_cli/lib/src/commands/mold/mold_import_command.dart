import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_import_git_command.dart';
import 'package:foundry_cli/src/commands/mold/mold_import_local_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.mold_import_command}
/// The `mold import` resource command group.
///
/// Groups subcommands that import a mold from an external source into
/// `./<name>/` under the current directory. See [MoldImportGitCommand] for
/// `foundry mold import git` and [MoldImportLocalCommand] for
/// `foundry mold import local`.
/// {@endtemplate}
class MoldImportCommand extends Command<int> {
  /// {@macro foundry_cli.mold_import_command}
  MoldImportCommand({required Logger logger}) {
    addSubcommand(MoldImportGitCommand(logger: logger));
    addSubcommand(MoldImportLocalCommand(logger: logger));
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      'Import a mold from an external source into ./<name>/.';
}
