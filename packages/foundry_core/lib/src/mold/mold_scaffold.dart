import 'package:foundry_core/src/version.dart';
import 'package:path/path.dart' as p;

/// The `foundry_core` version constraint written into scaffolded mold pubspecs.
///
/// Mirrors [foundryCoreVersion] so a freshly derived or initialized mold
/// resolves against a compatible `foundry_core` release.
String get scaffoldFoundryCoreConstraint => '^$foundryCoreVersion';

final RegExp _validMoldNamePattern = RegExp(r'^[a-z_][a-z0-9_]*$');

/// Whether [name] is a valid mold package name: lowercase letters, digits,
/// and underscores, and must not start with a digit.
bool isValidMoldName(String name) => _validMoldNamePattern.hasMatch(name);

/// Sanitizes [raw] into a mold package name.
///
/// Lowercases [raw], replaces characters outside `[a-z0-9_]` with `_`, and
/// prefixes `mold_` when the result would start with a digit. Empty results
/// become `mold`.
String sanitizeMoldName(String raw) {
  final normalized = raw.toLowerCase().replaceAll(
        RegExp('[^a-z0-9_]'),
        '_',
      );
  if (normalized.isEmpty) {
    return 'mold';
  }
  return RegExp('^[0-9]').hasMatch(normalized)
      ? 'mold_$normalized'
      : normalized;
}

/// Derives a default mold name from [path]'s basename.
String defaultMoldNameFromPath(String path) {
  return sanitizeMoldName(p.basename(p.normalize(path)));
}

/// Root `pubspec.yaml` contents for a scaffolded or derived mold named [name].
String moldScaffoldPubspecContents(String name) => '''
name: $name
description: A Foundry mold.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core: $scaffoldFoundryCoreConstraint
''';

/// Stub `variables.dart` contents for a scaffolded or derived mold.
const String moldScaffoldVariablesContents = '''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''';
