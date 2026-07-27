import 'dart:io';

import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_pubspec.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A loaded mold definition combining package metadata and variable schema.
@immutable
final class Mold {
  /// Creates a [Mold].
  const Mold({
    required this.directory,
    required this.pubspec,
    required this.variableGroup,
  });

  /// Absolute path to the mold root directory.
  final Directory directory;

  /// Parsed root `pubspec.yaml` metadata.
  final MoldPubspec pubspec;

  /// Variable schema supplied by the caller (typically a live in-memory group).
  final FoundryVariableGroup variableGroup;

  /// Shorthand for [MoldPubspec.name].
  String get name => pubspec.name;

  /// Shorthand for [MoldPubspec.description].
  String get description => pubspec.description;

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
