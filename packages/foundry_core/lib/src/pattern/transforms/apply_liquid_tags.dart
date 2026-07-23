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
  return _liquidTagPatterns.fold(content, (resolved, pattern) {
    final regex = RegExp(pattern, dotAll: true);
    return resolved.replaceAllMapped(regex, (match) {
      match as RegExpMatch;
      return _resolveLiquidTagMatch(match);
    });
  });
}

/// A liquid-tag annotation parked before liquidize so its braces stay live.
typedef ParkedLiquidTag = ({
  String tag,
  bool dropLeading,
  bool dropTrailing,
});

/// Parks liquid-tag comment tokens as placeholders so a later liquidize pass
/// does not escape their braces.
///
/// Only the comment token itself is replaced (newlines around it are left in
/// place so later block annotations such as insert/replace still parse).
/// [restoreParkedLiquidTags] writes the live tag and applies any `x`
/// whitespace flags.
({String content, List<ParkedLiquidTag> replacements}) parkLiquidTagAnnotations(
  String content,
) {
  final replacements = <ParkedLiquidTag>[];
  final parked = _liquidTagTokenPatterns.fold(content, (resolved, pattern) {
    final regex = RegExp(pattern, dotAll: true);
    return resolved.replaceAllMapped(regex, (match) {
      match as RegExpMatch;
      final index = replacements.length;
      replacements.add(
        (
          tag: match.namedGroup('liquidTag') ?? '',
          dropLeading: (match.namedGroup('dropLeading') ?? '').isNotEmpty,
          dropTrailing: (match.namedGroup('dropTrailing') ?? '').isNotEmpty,
        ),
      );
      return '$_placeholderPrefix$index$_placeholderSuffix';
    });
  });
  return (content: parked, replacements: replacements);
}

/// Restores placeholders produced by [parkLiquidTagAnnotations].
///
/// Applies optional `x` whitespace flags against adjacent whitespace at
/// restore time (after other annotation transforms have run).
String restoreParkedLiquidTags(
  String content, {
  required List<ParkedLiquidTag> replacements,
}) {
  if (replacements.isEmpty) {
    return content;
  }
  var restored = content;
  for (var i = 0; i < replacements.length; i++) {
    final placeholder = '$_placeholderPrefix$i$_placeholderSuffix';
    final parked = replacements[i];
    final index = restored.indexOf(placeholder);
    if (index < 0) {
      continue;
    }
    var start = index;
    var end = index + placeholder.length;
    if (parked.dropLeading) {
      while (start > 0 && _isWhitespace(restored.codeUnitAt(start - 1))) {
        start--;
      }
    }
    if (parked.dropTrailing) {
      while (end < restored.length && _isWhitespace(restored.codeUnitAt(end))) {
        end++;
      }
    }
    restored = restored.replaceRange(start, end, parked.tag);
  }
  return restored;
}

const _placeholderPrefix = '<<FOUNDRY_LIQUID_TAG_';
const _placeholderSuffix = '>>';

/// `{{…}}` or `{%…%}` (non-greedy inner match).
const _liquidTag = '(?:{{.*?}}|{%.*?%})';

/// Full match including adjacent whitespace (used by [applyLiquidTags]).
final List<String> _liquidTagPatterns = [
  [
    r'(?<leading>\s*)\/\*(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    r')(?<dropTrailing>x)?\*\/(?<trailing>\s*)',
  ].join(),
  [
    r'(?<leading>\s*)#(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    r')(?<dropTrailing>x)?#(?<trailing>\s*)',
  ].join(),
  [
    r'(?<leading>\s*)<!--(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    r')(?<dropTrailing>x)?-->(?<trailing>\s*)',
  ].join(),
];

/// Comment token only — no adjacent whitespace (used when parking so block
/// annotation newlines stay intact until restore).
final List<String> _liquidTagTokenPatterns = [
  [
    r'\/\*(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    r')(?<dropTrailing>x)?\*\/',
  ].join(),
  [
    '#(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    ')(?<dropTrailing>x)?#',
  ].join(),
  [
    '<!--(?<dropLeading>x)?(?<liquidTag>',
    _liquidTag,
    ')(?<dropTrailing>x)?-->',
  ].join(),
];

String _resolveLiquidTagMatch(RegExpMatch match) {
  final liquidTag = match.namedGroup('liquidTag') ?? '';
  final keepLeading = (match.namedGroup('dropLeading') ?? '').isEmpty;
  final keepTrailing = (match.namedGroup('dropTrailing') ?? '').isEmpty;
  final leading = match.namedGroup('leading') ?? '';
  final trailing = match.namedGroup('trailing') ?? '';
  return [
    if (keepLeading) leading,
    liquidTag,
    if (keepTrailing) trailing,
  ].join();
}

bool _isWhitespace(int codeUnit) {
  return codeUnit == 0x09 || // tab
      codeUnit == 0x0A || // line feed
      codeUnit == 0x0D || // carriage return
      codeUnit == 0x20; // space
}
