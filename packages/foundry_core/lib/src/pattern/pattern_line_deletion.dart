import 'package:meta/meta.dart';

/// An inclusive, zero-based line range within a pattern file.
@immutable
final class PatternLineRange {
  /// Creates a [PatternLineRange].
  const PatternLineRange({
    required this.start,
    required this.end,
  });

  /// First line to delete (inclusive, zero-based).
  final int start;

  /// Last line to delete (inclusive, zero-based).
  final int end;

  /// Whether [lineNumber] falls within this range.
  bool contains(int lineNumber) => start <= lineNumber && lineNumber <= end;
}

/// Line ranges to drop from a specific pattern file.
///
/// Declared under `lineDeletions` in `.foundry/pattern.yaml`. [filePath] is
/// relative to the pattern root.
@immutable
final class PatternLineDeletion {
  /// Creates a [PatternLineDeletion].
  const PatternLineDeletion({
    required this.filePath,
    required this.ranges,
  });

  /// Path to the target file, relative to the pattern root.
  final String filePath;

  /// Ranges of lines to remove from [filePath].
  final List<PatternLineRange> ranges;
}
