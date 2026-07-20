import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_scaffold.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;

/// {@template foundry_cli.pattern_init_command}
/// `foundry pattern init [--name=<name>]`
///
/// Scaffolds a pattern marker (`.foundry/pattern.yaml`) and README stub in
/// the current directory.
/// {@endtemplate}
class PatternInitCommand extends Command<int> {
  /// {@macro foundry_cli.pattern_init_command}
  PatternInitCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser.addOption(
      nameOptionName,
      help: 'The pattern name. Defaults to the current directory name.',
    );
  }

  /// The option name used to override the scaffolded pattern's name.
  static const String nameOptionName = 'name';

  @override
  String get name => 'init';

  @override
  String get description =>
      'Scaffold a pattern marker (.foundry/pattern.yaml) and README in the '
      'current directory.';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory the pattern is scaffolded into. Defaults to the process cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    final providedName = argResults!.option(nameOptionName);
    final patternName =
        (providedName ?? defaultPatternName(workingDirectory)).trim();

    if (!isValidPatternName(patternName)) {
      logger.error(
        'Invalid pattern name "$patternName": must be a non-empty string.',
      );
      return FoundryExitCode.userError.code;
    }

    try {
      await scaffoldPattern(directory: workingDirectory, name: patternName);
    } on PatternScaffoldException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }

    logger.info(
      'Scaffolded pattern "$patternName" in ${workingDirectory.path}',
    );
    return FoundryExitCode.success.code;
  }
}
