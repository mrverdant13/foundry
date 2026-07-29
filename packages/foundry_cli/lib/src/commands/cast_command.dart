import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/display_path.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

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

/// Reads the contents of a `--vars-file` path.
///
/// Production code uses [File.readAsString]; tests inject failures.
typedef VarsFileContentsReader = Future<String> Function(File file);

/// Launches a mold cast session (batch, interactive, or finish-only) via the
/// synthetic helper package.
///
/// Production code uses [launchBatchMoldCastSession]; tests inject fakes.
typedef BatchMoldCastSessionLauncher = Future<MoldCastSessionLaunchResult>
    Function({
  required String moldPath,
  required String outputPath,
  Map<String, Object?>? varsFileValues,
  Map<String, Object?>? seededValues,
  String? varsFlag,
  bool force,
  bool noHooks,
  bool finishOnly,
});

/// {@template foundry_cli.cast_command}
/// `foundry cast <mold-path> --output=<dir> [--force] [--no-hooks]`
/// `[--vars=<k=v,…>] [--vars-file=<path>]`
///
/// Launches a mold cast session so live `variables.dart` callbacks run in a
/// helper process, then persists `.foundry/last_cast.json` from the session's
/// encodable vars projection. With `--vars` and/or `--vars-file`, the session
/// runs batch parse; otherwise it gathers through the Nocterm TUI inside that
/// process (or `FOUNDRY_E2E_VARS` for automated tests).
/// {@endtemplate}
class CastCommand extends Command<int> {
  /// {@macro foundry_cli.cast_command}
  CastCommand({
    required this.logger,
    Directory? workingDirectory,
    VarsFileContentsReader? readVarsFileContents,
    BatchMoldCastSessionLauncher? launchBatchSession,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        _readVarsFileContents =
            readVarsFileContents ?? ((file) => file.readAsString()),
        _launchBatchSession = launchBatchSession ?? launchBatchMoldCastSession {
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
            '(skips the interactive TUI). Object fields may use dotted paths '
            '(for example publish.host=…). A whole-object flag assignment '
            'cannot be combined with dotted children for the same path.',
      )
      ..addOption(
        varsFileOptionName,
        help: 'Path to a JSON object of variable values for batch cast '
            '(skips the interactive TUI). Prefer --vars-file for deep nests.',
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

  final VarsFileContentsReader _readVarsFileContents;
  final BatchMoldCastSessionLauncher _launchBatchSession;

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

    final hasVars = argResults!.wasParsed(varsOptionName);
    final hasVarsFile = argResults!.wasParsed(varsFileOptionName);
    final varsFileValues = await _readVarsFileValues(hasVarsFile: hasVarsFile);
    if (hasVarsFile && varsFileValues == null) {
      return FoundryExitCode.userError.code;
    }

    final result = await _launchBatchSession(
      moldPath: moldPath,
      outputPath: outputPath,
      varsFileValues: varsFileValues,
      varsFlag: hasVars ? argResults!.option(varsOptionName) : null,
      force: force,
      noHooks: noHooks,
    );

    switch (result) {
      case MoldCastSessionLaunchSuccess(
          :final artifactCount,
          :final vars,
          :final exitCode,
        ):
        await writeCastState(
          CastState(
            moldPath: rawMoldPath,
            outputPath: rawOutputPath,
            vars: vars,
            timestamp: DateTime.now(),
          ),
          cwd: workingDirectory,
        );
        final displayOutputPath = formatDisplayPath(
          outputPath,
          cwd: workingDirectory.path,
        );
        logger
          ..info('✓ Cast completed')
          ..info(
            '✓ $artifactCount artifacts generated at $displayOutputPath',
          );
        return exitCode;
      case MoldCastSessionLaunchFailure(
          :final kind,
          :final message,
          :final exitCode,
        ):
        if (kind == 'cancel') {
          await _removeOutputIfEmpty(outputPath);
          logger.info('Cast cancelled.');
          return exitCode;
        }
        logger.error(message);
        if (kind == 'hook' || kind == 'gather') {
          // Prepare / gather may have created --output before failing; match
          // prior interactive cleanup when the directory is still empty.
          await _removeOutputIfEmpty(outputPath);
        }
        return exitCode;
      case MoldCastSessionDescribeSuccess():
        logger.error('Internal error: unexpected describe session result.');
        return FoundryExitCode.internalError.code;
    }
  }

  /// Removes [outputPath] when it exists and contains no entries (best-effort
  /// cleanup after prepare/gather failure or cancelled gather).
  ///
  /// When the directory is non-empty (for example a prepare hook wrote files
  /// before abort), leaves it in place and warns so leftover output is not
  /// silent.
  Future<void> _removeOutputIfEmpty(String outputPath) async {
    final directory = Directory(outputPath);
    if (!directory.existsSync()) {
      return;
    }
    if (directory.listSync().isEmpty) {
      await directory.delete();
      return;
    }
    logger.warn(
      'Output directory "$outputPath" is not empty; left in place after '
      'aborted cast.',
    );
  }

  /// Reads and decodes `--vars-file` when [hasVarsFile] is true.
  ///
  /// Returns `null` after logging a user-facing error when the file cannot be
  /// read or decoded. Returns `null` without error when [hasVarsFile] is false.
  Future<Map<String, Object?>?> _readVarsFileValues({
    required bool hasVarsFile,
  }) async {
    if (!hasVarsFile) {
      return null;
    }

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
      contents = await _readVarsFileContents(varsFile);
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
    return Map<String, Object?>.from(decoded);
  }
}
