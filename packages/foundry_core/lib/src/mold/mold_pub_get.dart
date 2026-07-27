import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Runs `dart pub get` for [moldDirectory] so mold dependencies resolve.
///
/// Throws [MoldLoadException] when dependency resolution fails.
Future<void> ensureMoldDependencies(Directory moldDirectory) async {
  final pubspecFile = File(p.join(moldDirectory.path, 'pubspec.yaml'));
  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: moldDirectory.path,
  );

  if (result.exitCode != 0) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: pubspecFile.path,
        message: describePubGetFailure(
          stdout: '${result.stdout}',
          stderr: '${result.stderr}',
        ),
      ),
    ]);
  }

  verifyMoldPackageConfig(moldDirectory);
}

/// Builds the error message used when `dart pub get` exits non-zero.
///
/// Exposed for unit tests covering empty and non-empty process output.
@visibleForTesting
String describePubGetFailure({
  required String stdout,
  required String stderr,
}) {
  final output = '$stdout$stderr'.trim();
  return output.isEmpty
      ? 'dart pub get failed for the mold package.'
      : 'dart pub get failed: $output';
}

/// Verifies that [moldDirectory] contains a generated package config file.
///
/// Exposed for unit tests covering post-`pub get` validation.
@visibleForTesting
void verifyMoldPackageConfig(Directory moldDirectory) {
  final packageConfig = File(
    p.join(moldDirectory.path, '.dart_tool', 'package_config.json'),
  );
  if (!packageConfig.existsSync()) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: packageConfig.path,
        message: 'Missing package config after running dart pub get.',
      ),
    ]);
  }
}

/// Returns the mold package config path after [ensureMoldDependencies].
String moldPackageConfigPath(Directory moldDirectory) {
  return p.join(moldDirectory.path, '.dart_tool', 'package_config.json');
}
