import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/src/pattern/pattern_ignore.dart';
import 'package:foundry_core/src/pattern/pattern_inspector.dart';
import 'package:foundry_core/src/pattern/pattern_line_deletion.dart';
import 'package:foundry_core/src/pattern/pattern_replacement.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_pattern_content.dart';
import 'package:foundry_core/src/pattern/transforms/resolve_template_relative_path.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';
import 'package:path/path.dart' as p;

/// Relative path segments that are never copied into a mold `template/`.
///
/// The pattern marker lives under `.foundry/` and is not template content.
const _excludedTemplatePrefixes = {'.foundry'};

/// Writes a liquidized `template/` tree under [templateRoot] from the pattern
/// at [patternRootPath], applying [ignoreGlobs], [lineDeletions], and
/// [replacements].
///
/// Creates [templateRoot] when missing. Existing files under [templateRoot] are
/// left untouched unless overwritten by a matching pattern file.
///
/// Binary files (NUL bytes) are copied unchanged (path replacements still
/// apply). Text files are resolved via [resolvePatternContent] (line
/// deletions, liquidize pre-pass, content replacements, remotions,
/// replace blocks, then insert blocks).
/// Destination paths are renamed with the same [replacements] list.
/// `.foundry/` is always excluded even when not listed in [ignoreGlobs].
///
/// Throws [TemplatePathReplacementException] when a path replacement would
/// produce an absolute path or escape [templateRoot].
Future<void> writeLiquidizedTemplateFromPattern({
  required Directory templateRoot,
  required String patternRootPath,
  required List<String> ignoreGlobs,
  List<PatternLineDeletion> lineDeletions = const [],
  List<PatternReplacement> replacements = const [],
}) async {
  await templateRoot.create(recursive: true);

  final ignoreMatchers = compilePatternIgnoreMatchers(ignoreGlobs);
  final files = enumeratePatternFiles(patternRootPath);

  for (final file in files) {
    final relative = p.relative(file.path, from: patternRootPath);
    final relativePosix = p.posix.joinAll(p.split(relative));
    if (_shouldSkipTemplatePath(relativePosix, ignoreMatchers)) {
      continue;
    }

    final destinationPath = resolveTemplateRelativePath(
      relativePosixPath: relativePosix,
      templateRootPath: templateRoot.path,
      replacements: replacements,
    );
    final destinationFile = File(destinationPath);
    await destinationFile.parent.create(recursive: true);
    await _copyPatternFileToTemplate(
      source: file,
      destination: destinationFile,
      relativePosixPath: relativePosix,
      lineDeletions: lineDeletions,
      replacements: replacements,
    );
  }
}

bool _shouldSkipTemplatePath(
  String relativePosix,
  List<PatternIgnoreMatcher> ignoreMatchers,
) {
  final firstSegment = relativePosix.split('/').first;
  if (_excludedTemplatePrefixes.contains(firstSegment)) {
    return true;
  }
  for (final matcher in ignoreMatchers) {
    if (matcher.matches(relativePosix)) {
      return true;
    }
  }
  return false;
}

Future<void> _copyPatternFileToTemplate({
  required File source,
  required File destination,
  required String relativePosixPath,
  required List<PatternLineDeletion> lineDeletions,
  required List<PatternReplacement> replacements,
}) async {
  final bytes = await source.readAsBytes();
  if (looksLikeBinaryTemplateBytes(bytes)) {
    await destination.writeAsBytes(bytes, flush: true);
    return;
  }

  final content = utf8.decode(bytes, allowMalformed: true);
  await destination.writeAsString(
    resolvePatternContent(
      content,
      relativePosixPath: relativePosixPath,
      lineDeletions: lineDeletions,
      replacements: replacements,
    ),
    flush: true,
  );
}
