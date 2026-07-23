import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/pattern_replacement.dart';
import 'package:foundry_core/src/pattern/transforms/apply_insert_blocks.dart';
import 'package:foundry_core/src/pattern/transforms/apply_line_deletions.dart';
import 'package:foundry_core/src/pattern/transforms/apply_liquid_tags.dart';
import 'package:foundry_core/src/pattern/transforms/apply_remotions.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replace_blocks.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replacements.dart';
import 'package:foundry_core/src/pattern/transforms/apply_spacing_groups.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_template_relative_path.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';

/// Resolves pattern file text into mold `template/` contents.
///
/// Transform order:
/// 1. [applyLineDeletions] for ranges whose [PatternLineDeletion.filePath]
///    matches [relativePosixPath] (non-matching entries are no-ops)
/// 2. Park liquid-tag annotations ([parkLiquidTagAnnotations]) so the liquidize
///    pre-pass does not escape their braces
/// 3. [liquidizeTemplateContents] escapes source `{{` / `{%` openers so
///    accidental braces survive later render as literals
/// 4. [applyReplacements] applies ordered regex replacements (may inject live
///    Liquid tags such as `{{ package_name }}`)
/// 5. [applyRemotions] resolves `drop` markers and `remove-start` /
///    `remove-end` blocks (C-style, hash, and HTML comment flavors)
/// 6. [applyReplaceBlocks] resolves `replace-start` / `with` / `replace-end`
///    blocks (C-style, hash, and HTML comment flavors)
/// 7. [applyInsertBlocks] resolves `insert-start` / `insert-end` blocks
///    (C-style, hash, and HTML comment flavors)
/// 8. [applyLiquidTags] unwraps `{{…}}` / `{%…%}` from comment wrappers
///    (including tags introduced by earlier annotation steps)
/// 9. [restoreParkedLiquidTags] restores parked annotations as live Liquid
/// 10. [applySpacingGroups] expands `w <actions> w` markers (`Nv` newlines,
///     `N>` spaces)
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
  final parked = parkLiquidTagAnnotations(withoutDeletedLines);
  final liquidized = liquidizeTemplateContents(parked.content);
  final withReplacements = applyReplacements(
    input: liquidized,
    replacements: replacements,
  );
  final withRemotions = applyRemotions(content: withReplacements);
  final withReplaceBlocks = applyReplaceBlocks(content: withRemotions);
  final withInsertBlocks = applyInsertBlocks(content: withReplaceBlocks);
  final withLiquidTags = applyLiquidTags(content: withInsertBlocks);
  final withRestoredTags = restoreParkedLiquidTags(
    withLiquidTags,
    replacements: parked.replacements,
  );
  return applySpacingGroups(content: withRestoredTags);
}
