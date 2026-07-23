/// Unwraps Liquid tags from comment wrappers in [content].
///
/// Supports C-style (`/* */`), hash (`# #`), and HTML (`<!-- -->`) comment
/// flavors for both `{{…}}` and `{%…%}` tags. Optional `x` flags before or
/// after the tag drop adjacent whitespace on that side:
///
/// - `x` before the tag (e.g. `/*x{{name}}*/`) drops leading whitespace
/// - `x` after the tag (e.g. `#{{name}}x#`) drops trailing whitespace
/// - Without a flag, adjacent whitespace on that side is kept
String applyLiquidTags({required String content}) {
  return _mapLiquidTagAnnotations(content, (resolved) => resolved);
}

/// Parks liquid-tag annotations as placeholders so a later liquidize pass does
/// not escape their braces.
///
/// Each match is resolved the same way as [applyLiquidTags] (tag extracted,
/// optional `x` whitespace flags applied). The returned content replaces each
/// annotation with a placeholder; [restoreParkedLiquidTags] puts the live
/// resolved strings back.
({String content, List<String> replacements}) parkLiquidTagAnnotations(
  String content,
) {
  final replacements = <String>[];
  final parked = _mapLiquidTagAnnotations(content, (resolved) {
    final index = replacements.length;
    replacements.add(resolved);
    return '$_placeholderPrefix$index$_placeholderSuffix';
  });
  return (content: parked, replacements: replacements);
}

/// Restores placeholders produced by [parkLiquidTagAnnotations].
String restoreParkedLiquidTags(
  String content, {
  required List<String> replacements,
}) {
  if (replacements.isEmpty) {
    return content;
  }
  var restored = content;
  for (var i = 0; i < replacements.length; i++) {
    restored = restored.replaceAll(
      '$_placeholderPrefix$i$_placeholderSuffix',
      replacements[i],
    );
  }
  return restored;
}

const _placeholderPrefix = '<<FOUNDRY_LIQUID_TAG_';
const _placeholderSuffix = '>>';

/// `{{…}}` or `{%…%}` (non-greedy inner match).
const _liquidTag = r'(?:{{.*?}}|{%.*?%})';

const _liquidTagPatterns = [
  r'(?<leading>\s*)\/\*(?<dropLeading>x)?(?<liquidTag>'
      '$_liquidTag'
      r')(?<dropTrailing>x)?\*\/(?<trailing>\s*)',
  r'(?<leading>\s*)#(?<dropLeading>x)?(?<liquidTag>'
      '$_liquidTag'
      r')(?<dropTrailing>x)?#(?<trailing>\s*)',
  r'(?<leading>\s*)<!--(?<dropLeading>x)?(?<liquidTag>'
      '$_liquidTag'
      r')(?<dropTrailing>x)?-->(?<trailing>\s*)',
];

String _mapLiquidTagAnnotations(
  String content,
  String Function(String resolved) replace,
) {
  return _liquidTagPatterns.fold(content, (resolved, pattern) {
    final regex = RegExp(pattern, dotAll: true);
    return resolved.replaceAllMapped(regex, (match) {
      match as RegExpMatch;
      final liquidTag = match.namedGroup('liquidTag') ?? '';
      final keepLeading = (match.namedGroup('dropLeading') ?? '').isEmpty;
      final keepTrailing = (match.namedGroup('dropTrailing') ?? '').isEmpty;
      final leading = match.namedGroup('leading') ?? '';
      final trailing = match.namedGroup('trailing') ?? '';
      final replacement = [
        if (keepLeading) leading,
        liquidTag,
        if (keepTrailing) trailing,
      ].join();
      return replace(replacement);
    });
  });
}
