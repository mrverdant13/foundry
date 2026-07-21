import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/src/pattern/pattern_ignore.dart';
import 'package:foundry_core/src/pattern/pattern_inspector.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';
import 'package:path/path.dart' as p;

/// Relative path segments that are never copied into a mold `template/`.
///
/// The pattern marker lives under `.foundry/` and is not template content.
const _excludedTemplatePrefixes = {'.foundry'};

/// Writes a liquidized `template/` tree under [templateRoot] from the pattern
/// at [patternRootPath], applying [ignoreGlobs].
///
/// Creates [templateRoot] when missing. Existing files under [templateRoot] are
/// left untouched unless overwritten by a matching pattern file.
///
/// Binary files (NUL bytes) are copied unchanged. Text files that contain
/// Liquid-looking markers are escaped via [liquidizeTemplateContents].
/// `.foundry/` is always excluded even when not listed in [ignoreGlobs].
Future<void> writeLiquidizedTemplateFromPattern({
  required Directory templateRoot,
  required String patternRootPath,
  required List<String> ignoreGlobs,
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

    final destinationFile = File(p.join(templateRoot.path, relative));
    await destinationFile.parent.create(recursive: true);
    await _copyPatternFileToTemplate(
      source: file,
      destination: destinationFile,
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
}) async {
  final bytes = await source.readAsBytes();
  if (looksLikeBinaryTemplateBytes(bytes)) {
    await destination.writeAsBytes(bytes, flush: true);
    return;
  }

  final content = utf8.decode(bytes, allowMalformed: true);
  await destination.writeAsString(
    liquidizeTemplateContents(content),
    flush: true,
  );
}
