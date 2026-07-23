/// Expands spacing-group (`w`) annotations in [content].
///
/// The marker letter `w` stands for whitespace. Supports C-style (`/* */`),
/// hash (`# #`), and HTML (`<!-- -->`) comment flavors. Actions are
/// space-separated:
///
/// - `Nv` — emit `N` newline characters (e.g. `2v` → two newlines)
/// - `N>` — emit `N` space characters (e.g. `4>` → four spaces)
///
/// Contiguous whitespace on either side of the marker is always discarded;
/// only the spacing produced by the actions survives. An empty action list
/// (`/*w w*/`, `#w w#`, `<!--w w-->`, including the tight hash form `#ww#`)
/// removes the marker and merges the surrounding text.
String applySpacingGroups({required String content}) {
  return _groupPatterns.fold(content, (resolved, groupPattern) {
    final groupRegex = RegExp(groupPattern, dotAll: true);
    return resolved.replaceAllMapped(groupRegex, (match) {
      match as RegExpMatch;
      final spacingGroups = match.namedGroup('spacingGroups') ?? '';
      return spacingGroups.replaceAllMapped(_actionRegex, (actionMatch) {
        actionMatch as RegExpMatch;
        final actionTimes =
            int.tryParse(actionMatch.namedGroup('actionTimes') ?? '') ?? 0;
        final actionType = actionMatch.namedGroup('actionType') ?? '';
        return switch (actionType) {
              'v' => '\n',
              '>' => ' ',
              _ => '',
            } *
            actionTimes;
      });
    });
  });
}

const List<String> _groupPatterns = [
  r'\s*\/\*w ?(?<spacingGroups>(?:\d+[v>] ?)*) ?w\*\/\s*',
  r'\s*#w ?(?<spacingGroups>(?:\d+[v>] ?)*) ?w#\s*',
  r'\s*<!--w ?(?<spacingGroups>(?:\d+[v>] ?)*) ?w-->\s*',
];

final RegExp _actionRegex = RegExp(
  r'(?<actionTimes>\d+)(?<actionType>[v>]) ?',
  dotAll: true,
);
