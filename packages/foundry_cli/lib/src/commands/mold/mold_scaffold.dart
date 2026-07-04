import 'dart:io';

import 'package:path/path.dart' as p;

/// The `foundry_core` version constraint written into scaffolded mold
/// pubspecs.
///
/// Mirrors the constraint this CLI itself depends on so a freshly scaffolded
/// mold resolves against a compatible `foundry_core` release.
const String scaffoldFoundryCoreConstraint = '^0.0.1-dev.1';

final RegExp _validMoldNamePattern = RegExp(r'^[a-z_][a-z0-9_]*$');

/// Thrown when [scaffoldMold] cannot write the mold to its target
/// directory.
class MoldScaffoldException implements Exception {
  /// Creates a [MoldScaffoldException] with a user-facing [message].
  const MoldScaffoldException(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() => message;
}

/// Whether [name] is a valid mold package name: lowercase letters, digits,
/// and underscores, and must not start with a digit.
bool isValidMoldName(String name) => _validMoldNamePattern.hasMatch(name);

/// Derives a default mold name from [directory]'s basename.
///
/// The basename is lowercased and any character outside `[a-z0-9_]` is
/// replaced with an underscore; a name that would start with a digit is
/// prefixed with `mold_`.
String defaultMoldName(Directory directory) {
  final basename = p.basename(p.normalize(directory.absolute.path));
  final normalized = basename.toLowerCase().replaceAll(
        RegExp('[^a-z0-9_]'),
        '_',
      );
  return RegExp('^[0-9]').hasMatch(normalized)
      ? 'mold_$normalized'
      : normalized;
}

/// Scaffolds a new mold's root `pubspec.yaml`, `variables.dart`, `template/`,
/// and `hooks/` under [directory].
///
/// [name] becomes the mold's package name. Throws [MoldScaffoldException]
/// when any scaffold target already exists at [directory], to avoid
/// clobbering existing files or leaving a partially-scaffolded mold behind.
Future<void> scaffoldMold({
  required Directory directory,
  required String name,
}) async {
  final pubspecFile = File(p.join(directory.path, 'pubspec.yaml'));
  final variablesFile = File(p.join(directory.path, 'variables.dart'));
  final templateDir = Directory(p.join(directory.path, 'template'));
  final hooksDir = Directory(p.join(directory.path, 'hooks'));

  final conflicts = [
    if (pubspecFile.existsSync()) 'pubspec.yaml',
    if (variablesFile.existsSync()) 'variables.dart',
    if (templateDir.existsSync()) 'template/',
    if (hooksDir.existsSync()) 'hooks/',
  ];
  if (conflicts.isNotEmpty) {
    throw MoldScaffoldException(
      'A mold already exists at "${directory.path}" '
      '(${conflicts.join(', ')} already present).',
    );
  }

  await directory.create(recursive: true);
  await pubspecFile.writeAsString(_pubspecContents(name));
  await variablesFile.writeAsString(_variablesContents);
  await templateDir.create();
  await hooksDir.create();
}

String _pubspecContents(String name) => '''
name: $name
description: A Foundry mold.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core: $scaffoldFoundryCoreConstraint
''';

const String _variablesContents = '''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''';
