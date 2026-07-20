import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_cli/src/commands/finish_command.dart';
import 'package:foundry_cli/src/commands/mold/mold_command.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_command.dart';
import 'package:foundry_cli/src/commands/recast_command.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.foundry_command_runner}
/// The command runner for the `foundry` command-line interface.
///
/// Commands are organized around resources (for example `mold`, `pattern`),
/// with top-level commands for the primary cast workflow (`cast`, `recast`,
/// `finish`).
/// {@endtemplate}
class FoundryCommandRunner extends CommandRunner<int> {
  /// {@macro foundry_cli.foundry_command_runner}
  FoundryCommandRunner({Logger? logger})
      : logger = logger ?? Logger(),
        super(
          'foundry',
          'A toolchain for authoring, importing, and casting molds.',
        ) {
    argParser.addFlag(
      versionFlagName,
      negatable: false,
      help: 'Print the current version.',
    );
    addCommand(MoldCommand(logger: this.logger));
    addCommand(PatternCommand(logger: this.logger));
    addCommand(CastCommand(logger: this.logger));
    addCommand(RecastCommand(logger: this.logger));
    addCommand(FinishCommand(logger: this.logger));
  }

  /// The flag name used to print the current [foundryCliVersion].
  static const versionFlagName = 'version';

  /// The logger used to report command runner output.
  final Logger logger;

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      return await runCommand(topLevelResults) ?? FoundryExitCode.success.code;
    } on UsageException catch (e) {
      logger
        ..error(e.message)
        ..error(e.usage);
      return FoundryExitCode.userError.code;
    } on Object catch (e) {
      logger.error('$e');
      return FoundryExitCode.internalError.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag(versionFlagName)) {
      logger.info(foundryCliVersion);
      return FoundryExitCode.success.code;
    }
    return super.runCommand(topLevelResults);
  }
}
