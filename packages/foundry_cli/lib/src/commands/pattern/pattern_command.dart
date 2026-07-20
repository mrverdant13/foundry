import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_init_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.pattern_command}
/// The `pattern` resource command group.
///
/// Groups subcommands that author patterns. See [PatternInitCommand] for
/// `foundry pattern init`.
/// {@endtemplate}
class PatternCommand extends Command<int> {
  /// {@macro foundry_cli.pattern_command}
  PatternCommand({required Logger logger}) {
    addSubcommand(PatternInitCommand(logger: logger));
  }

  @override
  String get name => 'pattern';

  @override
  String get description => 'Author patterns.';
}
