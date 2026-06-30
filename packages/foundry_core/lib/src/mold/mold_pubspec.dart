import 'package:meta/meta.dart';

/// Parsed metadata from a mold's root `pubspec.yaml`.
@immutable
final class MoldPubspec {
  /// Creates a [MoldPubspec].
  const MoldPubspec({
    required this.name,
    required this.description,
    required this.version,
  });

  /// Package name used for import destination directory names.
  final String name;

  /// Short human-readable description of the mold.
  final String description;

  /// Package version declared in `pubspec.yaml`.
  final String version;
}
