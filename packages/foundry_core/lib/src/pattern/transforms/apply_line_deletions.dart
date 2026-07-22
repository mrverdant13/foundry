import 'dart:convert';

import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:path/path.dart' as p;

/// Drops configured line ranges from [content] when [relativePosixPath] matches.
///
/// [relativePosixPath] is the pattern-root-relative POSIX path of the file
/// being resolved (the same form used when writing `template/`).
/// [PatternLineDeletion.filePath] values are compared with [p.posix.equals].
///
/// Ranges use zero-based, inclusive line indices ([PatternLineRange]). Entries
/// whose [PatternLineDeletion.filePath] does not match [relativePosixPath] are
/// ignored (no-op). Line numbers past the end of [content] are ignored.
///
/// When any matching range applies, lines are rejoined with `\n` and a trailing
/// newline is always present (matching `writeln` semantics). When no matching
/// ranges apply, [content] is returned unchanged — including original newlines.
String applyLineDeletions({
  required String content,
  required String relativePosixPath,
  required List<PatternLineDeletion> lineDeletions,
}) {
  final applicableRanges = lineDeletions
      .where(
        (deletion) => p.posix.equals(deletion.filePath, relativePosixPath),
      )
      .expand((deletion) => deletion.ranges)
      .toList();
  if (applicableRanges.isEmpty) {
    return content;
  }

  final buffer = StringBuffer();
  for (final (lineIndex, lineContent) in LineSplitter.split(content).indexed) {
    final shouldDrop = applicableRanges.any(
      (range) => range.contains(lineIndex),
    );
    if (!shouldDrop) {
      buffer.writeln(lineContent);
    }
  }
  return buffer.toString();
}
