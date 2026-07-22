import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/transforms/apply_line_deletions.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';

/// Resolves pattern file text into mold `template/` contents.
///
/// Transform order:
/// 1. [applyLineDeletions] for ranges whose [PatternLineDeletion.filePath]
///    matches [relativePosixPath] (non-matching entries are no-ops)
/// 2. [liquidizeTemplateContents] so remaining Liquid-looking markers survive
///    later render as literals
///
/// This is the single entry point used when writing a pattern file into
/// `template/`. Binary files are not passed through this helper — copy them
/// unchanged.
String resolvePatternContent(
  String source, {
  String relativePosixPath = '',
  List<PatternLineDeletion> lineDeletions = const [],
}) {
  final withoutDeletedLines = applyLineDeletions(
    content: source,
    relativePosixPath: relativePosixPath,
    lineDeletions: lineDeletions,
  );
  return liquidizeTemplateContents(withoutDeletedLines);
}
