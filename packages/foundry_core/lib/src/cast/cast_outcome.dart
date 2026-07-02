import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:meta/meta.dart';

/// Result of a successful `castMold` run.
@immutable
final class CastOutcome {
  /// Creates a [CastOutcome].
  const CastOutcome({
    required this.mold,
    required this.outputDirectory,
    required this.writtenFiles,
    required this.values,
  });

  /// The mold that was cast.
  final Mold mold;

  /// The `--output` directory files were rendered into.
  final Directory outputDirectory;

  /// Files written by template rendering, in template-relative path order.
  final List<File> writtenFiles;

  /// Final gathered cast values, including hook mutations and resolved
  /// variables, as written to `.foundry/last_cast.json` by the CLI.
  final Map<String, Object?> values;

  /// Number of files rendered to [outputDirectory].
  int get artifactCount => writtenFiles.length;
}
