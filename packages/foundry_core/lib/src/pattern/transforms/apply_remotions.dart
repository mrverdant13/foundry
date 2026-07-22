/// Resolves `drop` markers and `remove-start` / `remove-end` blocks in
/// [content].
///
/// Supports C-style (`/* */`), hash (`# #`), and HTML (`<!-- -->`) comment
/// flavors. Optional `x-` / `-x` flags on remove blocks control whether
/// leading or trailing whitespace adjacent to the matched block is retained:
///
/// - `x-` before `remove-start` drops leading whitespace
/// - `-x` after `remove-end` drops trailing whitespace
/// - Without a flag, adjacent whitespace on that side is kept
///
/// `drop` removes from the marker through end of file. Paired remove blocks
/// remove the markers and everything between them.
String applyRemotions({required String content}) {
  final afterDropContent = content.replaceAll(_blockDropRegex, '');

  return _blockRemotionPatterns.fold(afterDropContent, (resolved, pattern) {
    final regex = RegExp(pattern, dotAll: true);
    return resolved.replaceAllMapped(regex, (match) {
      match as RegExpMatch;
      final keepLeading = (match.namedGroup('dropLeading') ?? '').isEmpty;
      final keepTrailing = (match.namedGroup('dropTrailing') ?? '').isEmpty;
      final leading = match.namedGroup('leading') ?? '';
      final trailing = match.namedGroup('trailing') ?? '';
      return [
        if (keepLeading) leading,
        if (keepTrailing) trailing,
      ].join();
    });
  });
}

final RegExp _blockDropRegex = RegExp(
  [
    r'\/\*drop\*\/.*',
    '#drop#.*',
    '<!--drop-->.*',
  ].map((pattern) => '(?:$pattern)').join('|'),
  dotAll: true,
);

const List<String> _blockRemotionPatterns = [
  r'(?<leading>\s*)\/\*(?<dropLeading>x-)?remove-start\*\/.*?\/\*remove-end(?<dropTrailing>-x)?\*\/(?<trailing>\s*)',
  r'(?<leading>\s*)#(?<dropLeading>x-)?remove-start#.*?#remove-end(?<dropTrailing>-x)?#(?<trailing>\s*)',
  r'(?<leading>\s*)<!--(?<dropLeading>x-)?remove-start-->.*?<!--remove-end(?<dropTrailing>-x)?-->(?<trailing>\s*)',
];
