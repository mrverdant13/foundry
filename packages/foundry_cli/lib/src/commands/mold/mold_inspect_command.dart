import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, MoldIssueSeverity, inspectMold;
import 'package:path/path.dart' as p;

/// {@template foundry_cli.mold_inspect_command}
/// `foundry mold inspect [<path>]`
///
/// Analyzes a mold, reporting structural issues. Defaults to the current
/// directory when no path is given.
/// {@endtemplate}
class MoldInspectCommand extends Command<int> {
  /// {@macro foundry_cli.mold_inspect_command}
  MoldInspectCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current;

  @override
  String get name => 'inspect';

  @override
  String get description => 'Analyze a mold, reporting structural issues.';

  @override
  String get invocation => '${runner!.executableName} mold inspect [<path>]';

  /// The logger used to report command output.
  final Logger logger;

  /// The directory `<path>` is resolved against when relative or omitted.
  final Directory workingDirectory;

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

    logger.info('Mold "${report.mold!.name}" is valid.');
    return FoundryExitCode.success.code;
  }
}
