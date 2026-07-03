import 'dart:io';

import 'package:foundry_core/src/mold/mold_import_exception.dart';
import 'package:foundry_core/src/mold/mold_import_support.dart';

/// Imports a local mold directory into `./<name>/` under
/// [destinationParent] (the process cwd when omitted), where `<name>`
/// comes from the mold's root `pubspec.yaml`.
///
/// Throws [MoldImportException] when [sourcePath] does not exist, is
/// missing `pubspec.yaml`, or the destination already exists and [force]
/// is `false`.
Future<Directory> importMoldFromLocal({
  required String sourcePath,
  Directory? destinationParent,
  bool force = false,
}) async {
  final source = Directory(sourcePath).absolute;
  if (!source.existsSync()) {
    throw MoldImportException(
      'Local mold source "${source.path}" does not exist.',
    );
  }

  return copyMoldToDestination(
    source: source,
    destinationParent: (destinationParent ?? Directory.current).absolute,
    force: force,
  );
}
