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
/// Throws [MoldImportException] when [source] is missing `pubspec.yaml`,
/// the destination would be the source itself (or a directory within it),
/// or the destination already exists and [force] is `false`.
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

Future<void> _copyDirectoryContents(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final destinationPath = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectoryContents(entity, Directory(destinationPath));
    } else if (entity is File) {
      await entity.copy(destinationPath);
    }
  }
}
