import 'dart:convert';
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

/// Reads persisted cast state from the process working directory.
typedef CastStateReader = Future<CastState> Function({Directory? cwd});

/// Reads persisted cast state for commands that depend on a prior cast.
///
/// Returns `null` after logging a user-facing error when the state file is
/// missing, invalid, or unreadable.
Future<CastState?> readCastStateOrReportError({
  required Logger logger,
  required Directory workingDirectory,
  CastStateReader readState = readCastState,
}) async {
  final statePath = castStateFile(cwd: workingDirectory).path;
  try {
    return await readState(cwd: workingDirectory);
  } on CastStateNotFoundException catch (exception) {
    logger.error('$exception');
    return null;
  } on FormatException catch (exception) {
    logger.error(
      'Cast state at "$statePath" is invalid or corrupted: $exception. '
      'Run `foundry cast` to create fresh state.',
    );
    return null;
  }
  // Manually catching this error to be more specific about the error message.
  // ignore: avoid_catching_errors
  on TypeError {
    logger.error(
      'Cast state at "$statePath" is invalid or corrupted. '
      'Run `foundry cast` to create fresh state.',
    );
    return null;
  } on FileSystemException catch (exception) {
    logger.error('Failed to read cast state at "$statePath": $exception');
    return null;
  }
}

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
/// `[--vars=<k=v,…>] [--vars-file=<path>]`
///
/// Loads the mold at `<mold-path>`, gathers its variables through the
/// Nocterm TUI (or batch flags), and casts an artifact at `--output`.
/// On success, persists `.foundry/last_cast.json` for `foundry recast` and
/// `foundry finish`.
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
      )
      ..addOption(
        varsOptionName,
        help: 'Comma-separated key=value pairs for batch cast '
            '(skips the interactive TUI).',
      )
      ..addOption(
        varsFileOptionName,
        help: 'Path to a JSON object of variable values for batch cast '
            '(skips the interactive TUI).',
      );
  }

  /// The option name used to provide the artifact output directory.
  static const String outputOptionName = 'output';

  /// The flag name used to allow casting into a non-empty output directory.
  static const String forceOptionName = 'force';

  /// The flag name used to skip all lifecycle hooks.
  static const String noHooksOptionName = 'no-hooks';

  /// The option name used to supply batch cast values as key=value pairs.
  static const String varsOptionName = 'vars';

  /// The option name used to supply batch cast values from a JSON file.
  static const String varsFileOptionName = 'vars-file';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory `<mold-path>`, `--output`, and `--vars-file` are resolved
  /// against when relative. Also where `.foundry/last_cast.json` is written.
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
      '[--force] [--no-hooks] [--vars=<k=v,…>] [--vars-file=<path>]';

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

    final hasVars = argResults!.wasParsed(varsOptionName);
    final hasVarsFile = argResults!.wasParsed(varsFileOptionName);
    final Map<String, Object?> values;
    if (hasVars || hasVarsFile) {
      final batchValues = await _resolveBatchValues(
        variableGroup: mold.variableGroup,
        hasVars: hasVars,
        hasVarsFile: hasVarsFile,
      );
      if (batchValues == null) {
        return FoundryExitCode.userError.code;
      }
      values = batchValues;
    } else {
      final gathered = await _gatherVariables(
        variableGroup: mold.variableGroup,
        moldName: mold.name,
        moldDescription: mold.description,
      );
      if (gathered == null) {
        logger.info('Cast cancelled.');
        return FoundryExitCode.userError.code;
      }
      values = gathered;
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

  /// Reads `--vars-file` (when present), merges with `--vars`, and parses
  /// against [variableGroup].
  ///
  /// Returns `null` after logging a user-facing error when the file cannot be
  /// read/decoded or when parse/validation fails.
  Future<Map<String, Object?>?> _resolveBatchValues({
    required FoundryVariableGroup variableGroup,
    required bool hasVars,
    required bool hasVarsFile,
  }) async {
    Map<String, Object?>? varsFileValues;
    if (hasVarsFile) {
      final rawVarsFilePath = argResults!.option(varsFileOptionName)!;
      final varsFilePath = p.normalize(
        p.join(workingDirectory.path, rawVarsFilePath),
      );
      final varsFile = File(varsFilePath);
      if (!varsFile.existsSync()) {
        logger.error('Vars file "$rawVarsFilePath" does not exist.');
        return null;
      }

      final String contents;
      try {
        contents = await varsFile.readAsString();
      } on FileSystemException catch (exception) {
        logger.error(
          'Failed to read vars file "$rawVarsFilePath": $exception',
        );
        return null;
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(contents);
      } on FormatException catch (exception) {
        logger.error(
          'Vars file "$rawVarsFilePath" is not valid JSON: $exception',
        );
        return null;
      }
      if (decoded is! Map) {
        logger.error(
          'Vars file "$rawVarsFilePath" must contain a JSON object.',
        );
        return null;
      }
      varsFileValues = Map<String, Object?>.from(decoded);
    }

    final result = parseCastVariableInputs(
      variableGroup: variableGroup,
      varsFileValues: varsFileValues,
      varsFlag: hasVars ? argResults!.option(varsOptionName) : null,
    );
    switch (result) {
      case CastVariableInputsParseSuccess(:final rawValues):
        return rawValues;
      case CastVariableInputsParseFailure():
        logger.error('$result');
        return null;
    }
  }
}
