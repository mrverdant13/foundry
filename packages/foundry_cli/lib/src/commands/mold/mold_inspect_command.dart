import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/cast_session_describe.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldIssueSeverity, inspectMold;
import 'package:path/path.dart' as p;

/// Launches a describe-only mold cast session for inspect variable reporting.
typedef MoldInspectDescribeLauncher = Future<MoldCastSessionLaunchResult>
    Function({
  required String moldPath,
});

/// {@template foundry_cli.mold_inspect_command}
/// `foundry mold inspect [<path>]`
///
/// Analyzes a mold, reporting structural issues and live variable metadata.
/// Defaults to the current directory when no path is given.
/// {@endtemplate}
class MoldInspectCommand extends Command<int> {
  /// {@macro foundry_cli.mold_inspect_command}
  MoldInspectCommand({
    required this.logger,
    Directory? workingDirectory,
    MoldInspectDescribeLauncher? launchDescribeSession,
  })  : workingDirectory = workingDirectory ?? Directory.current,
        launchDescribeSession =
            launchDescribeSession ?? launchDescribeMoldCastSession;

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Analyze a mold, reporting structural issues and variable metadata.';

  @override
  String get invocation => '${runner!.executableName} mold inspect [<path>]';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory `<path>` is resolved against when relative or omitted.
  final Directory workingDirectory;

  /// Launches the describe-only session that reports live variable metadata.
  final MoldInspectDescribeLauncher launchDescribeSession;

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Too many arguments: expected at most one <path>.');
    }

    final moldPath = rest.isEmpty
        ? workingDirectory.path
        : p.normalize(p.join(workingDirectory.path, rest.single));

    final report = await inspectMold(moldPath);

    for (final issue in report.issues) {
      final message = '${issue.path}: ${issue.message}';
      switch (issue.severity) {
        case MoldIssueSeverity.error:
          logger.error(message);
        case MoldIssueSeverity.warning:
          logger.info('[WARN] $message');
      }
    }

    if (!report.isValid) {
      return FoundryExitCode.userError.code;
    }

    final describeResult = await launchDescribeSession(moldPath: moldPath);
    switch (describeResult) {
      case MoldCastSessionDescribeSuccess(:final variables):
        _logVariables(variables);
      case MoldCastSessionLaunchFailure(:final message, :final exitCode):
        logger.error(message);
        return exitCode;
      case MoldCastSessionLaunchSuccess():
        logger.error('Internal error: unexpected cast session result.');
        return FoundryExitCode.internalError.code;
    }

    logger.info('Mold "${report.mold!.name}" is valid.');
    return FoundryExitCode.success.code;
  }

  void _logVariables(List<MoldVariableDescription> variables) {
    if (variables.isEmpty) {
      return;
    }

    logger.info('Variables:');
    for (final variable in variables) {
      _logVariable(variable, indent: '  ');
    }
  }

  void _logVariable(
    MoldVariableDescription variable, {
    required String indent,
  }) {
    logger.info('$indent${variable.key} (${variable.kind}): ${variable.label}');
    final nestedIndent = '$indent  ';
    if (variable.description case final description?) {
      logger.info('${nestedIndent}description: $description');
    }
    if (variable.help case final help?) {
      logger.info('${nestedIndent}help: $help');
    }
    if (variable.placeholder case final placeholder?) {
      logger.info('${nestedIndent}placeholder: $placeholder');
    }
    if (variable.options.isNotEmpty) {
      logger.info('${nestedIndent}options:');
      for (final option in variable.options) {
        logger.info('$nestedIndent  - ${option.value}: ${option.label}');
      }
    }
    if (variable.fields.isNotEmpty) {
      logger.info('${nestedIndent}fields:');
      for (final field in variable.fields) {
        _logVariable(field, indent: '$nestedIndent  ');
      }
    }
    if (variable.item case final item?) {
      logger.info('${nestedIndent}item:');
      _logVariable(item, indent: '$nestedIndent  ');
    }
  }
}
