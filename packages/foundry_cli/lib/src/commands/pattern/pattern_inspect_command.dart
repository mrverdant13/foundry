import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_core/foundry_core.dart'
    show Logger, PatternInspectionReport, PatternIssueSeverity, inspectPattern;
import 'package:path/path.dart' as p;

/// {@template foundry_cli.pattern_inspect_command}
/// `foundry pattern inspect [<path>]`
///
/// Analyzes a pattern directory, reporting structure and ignore matches.
/// Defaults to the current directory when no path is given.
/// {@endtemplate}
class PatternInspectCommand extends Command<int> {
  /// {@macro foundry_cli.pattern_inspect_command}
  PatternInspectCommand({
    required this.logger,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current;

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Analyze a pattern, reporting structure and ignore matches.';

  @override
  String get invocation => '${runner!.executableName} pattern inspect [<path>]';

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

    final patternPath = rest.isEmpty
        ? workingDirectory.path
        : p.normalize(p.join(workingDirectory.path, rest.single));

    final report = await inspectPattern(patternPath);

    for (final issue in report.issues) {
      final message = '${issue.path}: ${issue.message}';
      switch (issue.severity) {
        case PatternIssueSeverity.error:
          logger.error(message);
        case PatternIssueSeverity.warning:
          logger.info('[WARN] $message');
      }
    }

    if (!report.isValid) {
      return FoundryExitCode.userError.code;
    }

    _writeReport(report);
    return FoundryExitCode.success.code;
  }

  void _writeReport(PatternInspectionReport report) {
    final nameLabel = report.name ?? '(unnamed)';
    logger
      ..info('Pattern: $nameLabel')
      ..info('Path: ${report.rootPath}')
      ..info('Marker: ${report.hasMarker ? 'yes' : 'no'}')
      ..info('Files: ${report.fileCount}');

    _writeListSection('Ignore globs', report.ignoreGlobs);
    _writeListSection('Top-level entries', report.topLevelEntries);
    _writeListSection('Ignored paths', report.ignoredPaths);
  }

  void _writeListSection(String title, List<String> values) {
    if (values.isEmpty) {
      logger.info('$title: (none)');
      return;
    }
    logger.info('$title:');
    for (final value in values) {
      logger.info('  - $value');
    }
  }
}
