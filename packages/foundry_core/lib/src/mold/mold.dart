import 'dart:io';

import 'package:foundry_core/src/mold/mold_manifest.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:meta/meta.dart';

/// A loaded mold definition combining manifest metadata and variable schema.
@immutable
final class Mold {
  /// Creates a [Mold].
  const Mold({
    required this.directory,
    required this.manifest,
    required this.variableGroup,
  });

  /// Absolute path to the mold root directory.
  final Directory directory;

  /// Parsed `mold.yaml` metadata.
  final MoldManifest manifest;

  /// Variable schema loaded from `variables.dart`.
  final FoundryVariableGroup variableGroup;

  /// Shorthand for [MoldManifest.name].
  String get name => manifest.name;

  /// Shorthand for [MoldManifest.description].
  String get description => manifest.description;
}
