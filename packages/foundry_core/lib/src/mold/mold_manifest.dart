import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:meta/meta.dart';

/// Parsed metadata from a mold's `mold.yaml` manifest.
@immutable
final class MoldManifest {
  /// Creates a [MoldManifest].
  const MoldManifest({
    required this.name,
    required this.description,
    this.hooks = const MoldHooks(),
  });

  /// Mold identifier used for import destination directory names.
  final String name;

  /// Short human-readable description of the mold.
  final String description;

  /// Optional lifecycle hook paths relative to the mold directory.
  final MoldHooks hooks;
}
