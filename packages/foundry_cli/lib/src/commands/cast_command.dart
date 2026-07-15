import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/tui/gather_cast_variables.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// Gathers cast variable values, returning `null` when the user cancels.
///
/// Production code uses [gatherCastVariablesInteractively] (the Nocterm
/// TUI); tests inject a fake implementation instead.
typedef CastVariableGatherer = Future<Map<String, Object?>?> Function({
  required FoundryVariableGroup variableGroup,
  required String moldName,
  required String moldDescription,
});

/// Runs the cast pipeline for a loaded mold.
///
/// Production code uses [castMold]; tests inject a fake implementation to
/// exercise error handling without building special-case molds.
typedef CastRunner = Future<CastOutcome> Function({
  required Mold mold,
  required String outputPath,
  required Map<String, Object?> values,
  bool force,
  bool noHooks,
});

/// {@template foundry_cli.cast_command}
/// `foundry cast <mold-path> --output=<dir> [--force] [--no-hooks]`
///
/// Loads the mold at `<mold-path>`, gathers its variables through the
/// Nocterm TUI, and casts an artifact at `--output` (REQUIREMENTS.md §3.2).
/// On success, persists `.foundry/last_cast.json` for `foundry recast` and
/// `foundry finish` (REQUIREMENTS.md §3.3).
/// {@endtemplate}
class CastCommand extends Command<int> {
  /// {@macro foundry_cli.cast_command}
  CastCommand({
    required this.logger,
    Directory? workingDirectory,
    CastVariableGatherer? gatherVariables,
    CastRunner? runCast,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _gatherVariables = gatherVariables ?? gatherCastVariablesInteractively,
        _runCast = runCast ?? castMold {
    argParser
      ..addOption(
        outputOptionName,
        help: 'The directory to cast the mold into.',
        mandatory: true,
      )
      ..addFlag(
        forceOptionName,
        negatable: false,
        help: 'Allow casting into a non-empty --output directory.',
      )
      ..addFlag(
        noHooksOptionName,
        negatable: false,
        help: 'Skip all lifecycle hooks (prepare, shape, finish).',
      );
  }

  /// The option name used to provide the artifact output directory.
  static const String outputOptionName = 'output';

  /// The flag name used to allow casting into a non-empty output directory.
  static const String forceOptionName = 'force';

  /// The flag name used to skip all lifecycle hooks.
  static const String noHooksOptionName = 'no-hooks';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory `<mold-path>` and `--output` are resolved against when
  /// relative. Also where `.foundry/last_cast.json` is written.
  final Directory workingDirectory;

  final CastVariableGatherer _gatherVariables;
  final CastRunner _runCast;

  @override
  String get name => 'cast';

  @override
  String get description => 'Cast a mold into an artifact.';

  @override
  String get invocation =>
      '${runner!.executableName} cast <mold-path> --output=<dir> '
      '[--force] [--no-hooks]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('A <mold-path> argument is required.');
    }
    if (rest.length > 1) {
      usageException('Too many arguments: expected exactly one <mold-path>.');
    }
    if (!argResults!.wasParsed(outputOptionName)) {
      usageException('Option $outputOptionName is mandatory.');
    }

    final rawMoldPath = rest.single;
    final rawOutputPath = argResults!.option(outputOptionName)!;
    final force = argResults!.flag(forceOptionName);
    final noHooks = argResults!.flag(noHooksOptionName);

    final moldPath = p.normalize(p.join(workingDirectory.path, rawMoldPath));
    final outputPath = p.normalize(
      p.join(workingDirectory.path, rawOutputPath),
    );

    final outputDirectory = Directory(outputPath);
    if (!force &&
        outputDirectory.existsSync() &&
        outputDirectory.listSync().isNotEmpty) {
      logger.error(
        'Output directory "$rawOutputPath" already exists and is not '
        'empty. Use --force to cast into it anyway.',
      );
      return FoundryExitCode.userError.code;
    }

    final Mold mold;
    try {
      mold = await loadMold(moldPath);
    } on MoldLoadException catch (exception) {
      for (final issue in exception.issues) {
        logger.error('${issue.path}: ${issue.message}');
      }
      return FoundryExitCode.userError.code;
    }

    final values = await _gatherVariables(
      variableGroup: mold.variableGroup,
      moldName: mold.name,
      moldDescription: mold.description,
    );
    if (values == null) {
      logger.info('Cast cancelled.');
      return FoundryExitCode.userError.code;
    }

    final CastOutcome outcome;
    try {
      outcome = await _runCast(
        mold: mold,
        outputPath: outputPath,
        values: values,
        force: force,
        noHooks: noHooks,
      );
    } on CastVariablesInvalidException catch (exception) {
      logger.error('Cast variables are invalid:');
      for (final fieldEntry in exception.validation.fieldErrors.entries) {
        for (final error in fieldEntry.value) {
          logger.error('  ${fieldEntry.key}: $error');
        }
      }
      for (final error in exception.validation.groupErrors) {
        logger.error('  $error');
      }
      return FoundryExitCode.userError.code;
    } on FoundryContextException catch (exception) {
      logger.error('Invalid cast variable input: ${exception.message}');
      return FoundryExitCode.userError.code;
    } on MoldHookException catch (exception) {
      logger.error(exception.toString());
      return FoundryExitCode.userError.code;
    } on TemplateRenderException catch (exception) {
      logger.error(exception.message);
      return FoundryExitCode.userError.code;
    }

    await writeCastState(
      CastState(
        moldPath: rawMoldPath,
        outputPath: rawOutputPath,
        vars: outcome.values,
        timestamp: DateTime.now(),
      ),
      cwd: workingDirectory,
    );

    logger
      ..info('✓ Cast completed')
      ..info('✓ ${outcome.artifactCount} artifacts generated at $outputPath');
    return FoundryExitCode.success.code;
  }
}
