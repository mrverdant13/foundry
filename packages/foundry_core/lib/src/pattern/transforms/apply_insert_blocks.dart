import 'dart:convert';

/// Resolves `insert-start` / `insert-end` blocks in [content].
///
/// Supports C-style (`/* */`), hash (`# #`), and HTML (`<!-- -->`) comment
/// flavors. Unlike replace blocks, there is no discarded scaffold region —
/// only the lines between the markers matter.
///
/// Each line between `insert-start` and `insert-end` must be comment-prefixed
/// for that flavor; leading and trailing whitespace on the line is trimmed
/// before the prefix is matched. The comment wrappers are stripped and the
/// inner text is emitted at the marker site. An empty body (`insert-start`
/// immediately followed by `insert-end`, with or without a blank separator
/// line) removes the markers and emits nothing.
///
/// Throws [FormatException] when an insert line is not comment-prefixed for
/// the matched flavor.
String applyInsertBlocks({required String content}) {
  const nl = r'(?:\r?\n)';
  final patternGroups = [
    (
      'C-style comment (expected // <content>)',
      [
        r'\/\*insert-start\*\/ *',
        nl,
        '(?:(?<insertion>.*?)',
        nl,
        r')? *\/\*insert-end\*\/',
      ].join(),
      r'^\/\/ (?<line>.*)$',
    ),
    (
      'hash comment (expected # <content>)',
      [
        '#insert-start# *',
        nl,
        '(?:(?<insertion>.*?)',
        nl,
        ')? *#insert-end#',
      ].join(),
      r'^# (?<line>.*)$',
    ),
    (
      'HTML comment (expected <!-- <content>-->)',
      [
        '<!--insert-start--> *',
        nl,
        '(?:(?<insertion>.*?)',
        nl,
        ')? *<!--insert-end-->',
      ].join(),
      r'^<!-- (?<line>.*?)-->$',
    ),
  ];

  return patternGroups.fold(content, (resolved, patternGroup) {
    final (flavorLabel, insertionPattern, linePattern) = patternGroup;
    final insertionRegex = RegExp(insertionPattern, dotAll: true);
    final lineRegex = RegExp(linePattern, dotAll: true);
    return resolved.replaceAllMapped(insertionRegex, (match) {
      match as RegExpMatch;
      final insertion = match.namedGroup('insertion') ?? '';
      final lines = LineSplitter.split(insertion);
      return lines.map((line) {
        final trimmedLine = line.trim();
        final lineMatch = lineRegex.firstMatch(trimmedLine);
        if (lineMatch == null) {
          throw FormatException(
            'Invalid insert-block line for $flavorLabel: '
            'expected a comment-prefixed line but got "$line".',
          );
        }
        final lineContent = lineMatch.namedGroup('line') ?? '';
        return lineContent;
      }).join('\n');
    });
  });
}
