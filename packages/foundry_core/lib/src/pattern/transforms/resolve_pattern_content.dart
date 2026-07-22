import 'package:foundry_core/src/rendering/template_liquidize.dart';

/// Resolves pattern file text into mold `template/` contents.
///
/// Currently applies [liquidizeTemplateContents] so Liquid-looking markers
/// survive later render as literals. This is the single entry point used when
/// writing a pattern file into `template/`.
///
/// Binary files are not passed through this helper — copy them unchanged.
String resolvePatternContent(String source) {
  return liquidizeTemplateContents(source);
}
