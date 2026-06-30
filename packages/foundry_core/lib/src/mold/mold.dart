import 'dart:io';

import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_manifest.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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

  /// Absolute path to the prepare hook when the standard file exists.
  File? get prepareHook {
    return _existingHookFile(MoldHooks.preparePath);
  }

  /// Absolute path to the shape hook when the standard file exists.
  File? get shapeHook {
    return _existingHookFile(MoldHooks.shapePath);
  }

  /// Absolute path to the finish hook when the standard file exists.
  File? get finishHook {
    return _existingHookFile(MoldHooks.finishPath);
  }

  File? _existingHookFile(String relativePath) {
    final file = File(p.join(directory.path, relativePath));
    return file.existsSync() ? file : null;
  }
}
