import 'package:meta/meta.dart';

/// A regex replacement applied to pattern file paths and contents.
///
/// Declared under `replacements` in `.foundry/pattern.yaml`. The [to] string
/// may use `${n}` capture-group interpolation when applied.
@immutable
final class PatternReplacement {
  /// Creates a [PatternReplacement].
  const PatternReplacement({
    required this.from,
    required this.to,
  });

  /// Pattern matched against paths and file contents.
  final RegExp from;

  /// Replacement string; may include `${n}` capture-group references.
  final String to;
}
