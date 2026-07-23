import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/pattern_replacement.dart';
import 'package:foundry_core/src/pattern/transforms/apply_insert_blocks.dart';
import 'package:foundry_core/src/pattern/transforms/apply_line_deletions.dart';
import 'package:foundry_core/src/pattern/transforms/apply_remotions.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replace_blocks.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replacements.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_template_relative_path.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';

/// Resolves pattern file text into mold `template/` contents.
///
/// Transform order:
/// 1. [applyLineDeletions] for ranges whose [PatternLineDeletion.filePath]
///    matches [relativePosixPath] (non-matching entries are no-ops)
/// 2. [liquidizeTemplateContents] escapes source `{{` / `{%` openers so
///    accidental braces survive later render as literals
/// 3. [applyReplacements] applies ordered regex replacements (may inject live
///    Liquid tags such as `{{ package_name }}`)
/// 4. [applyRemotions] resolves `drop` markers and `remove-start` /
///    `remove-end` blocks (C-style, hash, and HTML comment flavors)
/// 5. [applyReplaceBlocks] resolves `replace-start` / `with` / `replace-end`
///    blocks (C-style, hash, and HTML comment flavors)
/// 6. [applyInsertBlocks] resolves `insert-start` / `insert-end` blocks
///    (C-style, hash, and HTML comment flavors)
///
/// This is the single entry point used when writing a pattern file into
/// `template/`. Binary files are not passed through this helper — copy them
/// unchanged. Path renames use the same [replacements] list via
/// [resolveTemplateRelativePath] outside this helper.
String resolvePatternContent(
  String source, {
  String relativePosixPath = '',
  List<PatternLineDeletion> lineDeletions = const [],
  List<PatternReplacement> replacements = const [],
}) {
  final withoutDeletedLines = applyLineDeletions(
    content: source,
    relativePosixPath: relativePosixPath,
    lineDeletions: lineDeletions,
  );
  final liquidized = liquidizeTemplateContents(withoutDeletedLines);
  final withReplacements = applyReplacements(
    input: liquidized,
    replacements: replacements,
  );
  final withRemotions = applyRemotions(content: withReplacements);
  final withReplaceBlocks = applyReplaceBlocks(content: withRemotions);
  return applyInsertBlocks(content: withReplaceBlocks);
}
