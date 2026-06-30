import 'package:meta/meta.dart';

/// Parsed metadata from a mold's `mold.yaml` manifest.
@immutable
final class MoldManifest {
  /// Creates a [MoldManifest].
  const MoldManifest({
    required this.name,
    required this.description,
  });

  /// Mold identifier used for import destination directory names.
  final String name;

  /// Short human-readable description of the mold.
  final String description;
}
