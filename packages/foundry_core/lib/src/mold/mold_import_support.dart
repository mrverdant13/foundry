import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:foundry_core/src/mold/mold_import_exception.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

/// Reads the `name` field from a mold's root `pubspec.yaml` for import
/// destination naming.
///
/// Throws [MoldImportException] when the file cannot be read or parsed, or
/// is missing the required `name` field.
String readMoldNameForImport(File pubspecFile) {
  final String yamlContent;
  try {
    yamlContent = pubspecFile.readAsStringSync();
  } on FileSystemException {
    throw MoldImportException(
      'Missing required file "pubspec.yaml" at "${pubspecFile.path}".',
    );
  }

  try {
    final pubspec = Pubspec.parse(
      yamlContent,
      sourceUrl: Uri.file(pubspecFile.path),
    );
    return pubspec.name;
  } on ParsedYamlException catch (error) {
    throw MoldImportException(
      'Could not read mold name from "${pubspecFile.path}": '
      '${error.message}',
    );
  }
}

/// Copies [source] to `<destinationParent>/<name>`, where `<name>` comes
/// from the mold's root `pubspec.yaml`, and returns the destination
/// directory.
///
/// VCS and tool-generated directories (`.git`, `.dart_tool`) are skipped.
///
/// Throws [MoldImportException] when [source] is missing `pubspec.yaml`,
/// the mold name is not a safe single path segment, the destination would
/// be the source itself (or a directory within it), or the destination
/// already exists and [force] is `false`.
Future<Directory> copyMoldToDestination({
  required Directory source,
  required Directory destinationParent,
  required bool force,
}) async {
  final pubspecFile = File(p.join(source.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw MoldImportException(
      'Missing required file "pubspec.yaml" in "${source.path}".',
    );
  }

  final name = readMoldNameForImport(pubspecFile);
  _ensureSafeMoldName(name);
  final destination = Directory(p.join(destinationParent.path, name));

  final normalizedSource = p.normalize(source.absolute.path);
  final normalizedDestination = p.normalize(destination.absolute.path);
  if (normalizedSource == normalizedDestination ||
      p.isWithin(normalizedSource, normalizedDestination)) {
    throw MoldImportException(
      'Destination "${destination.path}" cannot be inside the source '
      'directory "${source.path}".',
    );
  }

  if (destination.existsSync()) {
    if (!force) {
      throw MoldImportException(
        'Destination "${destination.path}" already exists. Pass force to '
        'overwrite it.',
      );
    }
    await destination.delete(recursive: true);
  }

  await _copyDirectoryContents(source, destination);
  return destination;
}

/// Ensures [name] (the mold's `pubspec.yaml` `name` field) is safe to use
/// as a single destination directory segment.
///
/// Throws [MoldImportException] when [name] contains a path separator or
/// is a `.`/`..` segment, either of which would let the destination
/// resolve outside of `destinationParent` (and, with `force`, could cause
/// deletion outside of it).
void _ensureSafeMoldName(String name) {
  final isSingleSegment = !p.isAbsolute(name) && p.split(name).length == 1;
  if (!isSingleSegment || name == '.' || name == '..') {
    throw MoldImportException(
      'Mold name "$name" is not a valid destination directory name.',
    );
  }
}

/// Directory names excluded from mold copies, such as VCS metadata and
/// tool-generated caches that should never be part of an imported mold.
const _excludedDirectoryNames = {'.git', '.dart_tool'};

Future<void> _copyDirectoryContents(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final basename = p.basename(entity.path);
    if (entity is Directory) {
      if (_excludedDirectoryNames.contains(basename)) continue;
      final destinationPath = p.join(destination.path, basename);
      await _copyDirectoryContents(entity, Directory(destinationPath));
    } else if (entity is File) {
      final destinationPath = p.join(destination.path, basename);
      await entity.copy(destinationPath);
    }
  }
}
