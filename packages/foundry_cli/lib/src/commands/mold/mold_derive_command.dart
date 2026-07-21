import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldDeriveException, deriveMoldFromPattern;
import 'package:path/path.dart' as p;

/// {@template foundry_cli.mold_derive_command}
/// `foundry mold derive --pattern=<path> [--output=<dir>] [--force]`
///
/// Generates a starter mold package (Liquidized `template/`, stub
/// `variables.dart`, root `pubspec.yaml`, empty `hooks/`) from a pattern
/// directory.
/// {@endtemplate}
class MoldDeriveCommand extends Command<int> {
  /// {@macro foundry_cli.mold_derive_command}
  MoldDeriveCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current {
    argParser
      ..addOption(
        patternOptionName,
        help: 'The pattern directory to derive the mold from.',
        mandatory: true,
      )
      ..addOption(
        outputOptionName,
        help: 'Destination directory for the derived mold. Defaults to the '
            'current directory (requires --force when omitted, since that '
            'path already exists).',
      )
      ..addFlag(
        forceOptionName,
        negatable: false,
        help: 'Overwrite the destination directory if it already exists.',
      );
  }

  /// The option name used to provide the pattern directory path.
  static const String patternOptionName = 'pattern';

  /// The option name used to provide the derived mold destination.
  static const String outputOptionName = 'output';

  /// The flag name used to overwrite an existing destination.
  static const String forceOptionName = 'force';

  @override
  String get name => 'derive';

  @override
  String get description =>
      'Derive a starter mold package from a pattern directory.';

  @override
  String get invocation =>
      '${runner!.executableName} mold derive --pattern=<path> '
      '[--output=<dir>] [--force]';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory relative paths are resolved against. Defaults to cwd.
  final Directory workingDirectory;

  @override
  Future<int> run() async {
    if (!argResults!.wasParsed(patternOptionName)) {
      usageException('Option $patternOptionName is mandatory.');
    }

    final patternOption = argResults!.option(patternOptionName)!;
    final outputOption = argResults!.option(outputOptionName);
    final force = argResults!.flag(forceOptionName);

    final patternPath = p.normalize(
      p.join(workingDirectory.path, patternOption),
    );
    final destinationPath = outputOption == null
        ? workingDirectory.path
        : p.normalize(p.join(workingDirectory.path, outputOption));

    try {
      final destination = await deriveMoldFromPattern(
        patternPath: patternPath,
        destination: Directory(destinationPath),
        force: force,
      );
      logger.info('Derived mold at "${destination.path}".');
      return FoundryExitCode.success.code;
    } on MoldDeriveException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }
  }
}
