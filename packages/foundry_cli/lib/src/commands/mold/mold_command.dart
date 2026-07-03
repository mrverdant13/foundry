import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_init_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.mold_command}
/// The `mold` resource command group.
///
/// Groups subcommands that author, inspect, and import molds. See
/// [MoldInitCommand] for `foundry mold init`.
/// {@endtemplate}
class MoldCommand extends Command<int> {
  /// {@macro foundry_cli.mold_command}
  MoldCommand({required Logger logger}) {
    addSubcommand(MoldInitCommand(logger: logger));
  }

  @override
  String get name => 'mold';

  @override
  String get description => 'Author, inspect, and import molds.';
}
