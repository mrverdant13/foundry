import 'dart:convert';

/// Resolves `replace-start` / `with` / `replace-end` blocks in [content].
///
/// Supports C-style (`/* */`), hash (`# #`), and HTML (`<!-- -->`) comment
/// flavors. Scaffold text between `replace-start` and `with` is discarded.
/// Each line between `with` and `replace-end` must be comment-prefixed for
/// that flavor; the comment wrappers are stripped and the inner text is
/// emitted.
///
/// Optional `i<N>` on the `with` marker indents each replacement line by N
/// spaces (`/*with i2*/`, `#with i2#`, `<!--with i2-->`). Omitting `i<N>`
/// leaves indentation unchanged (zero extra spaces).
///
/// Throws [FormatException] when a replacement line is not comment-prefixed
/// for the matched flavor.
String applyReplaceBlocks({required String content}) {
  const nl = r'(?:\r?\n)';
  final patternGroups = [
    (
      'C-style comment (expected // <content>)',
      [
        r'\/\*replace-start\*\/ *',
        nl,
        '*.*?',
        nl,
        r'* *\/\*with(?: +i(?<indentation>\d+))?\*\/ *',
        nl,
        '(?<replacement>.*?)',
        nl,
        r' *\/\*replace-end\*\/',
      ].join(),
      r'\/\/ (?<line>.*)',
    ),
    (
      'hash comment (expected # <content>)',
      [
        '#replace-start# *',
        nl,
        '*.*?',
        nl,
        r'* *#with(?: +i(?<indentation>\d+))?# *',
        nl,
        '(?<replacement>.*?)',
        nl,
        ' *#replace-end#',
      ].join(),
      '# (?<line>.*)',
    ),
    (
      'HTML comment (expected <!-- <content>-->)',
      [
        '<!--replace-start--> *',
        nl,
        '*.*?',
        nl,
        r'* *<!--with(?: +i(?<indentation>\d+))?--> *',
        nl,
        '(?<replacement>.*?)',
        nl,
        ' *<!--replace-end-->',
      ].join(),
      '<!-- (?<line>.*)-->',
    ),
  ];

  return patternGroups.fold(content, (resolved, patternGroup) {
    final (flavorLabel, replacementPattern, linePattern) = patternGroup;
    final replacementRegex = RegExp(replacementPattern, dotAll: true);
    final lineRegex = RegExp(linePattern, dotAll: true);
    return resolved.replaceAllMapped(replacementRegex, (match) {
      match as RegExpMatch;
      final indentation =
          int.tryParse(match.namedGroup('indentation') ?? '') ?? 0;
      final replacement = match.namedGroup('replacement') ?? '';
      final lines = LineSplitter.split(replacement);
      return lines.map((line) {
        final lineMatch = lineRegex.firstMatch(line);
        if (lineMatch == null) {
          throw FormatException(
            'Invalid replace-block line for $flavorLabel: '
            'expected a comment-prefixed line but got "$line".',
          );
        }
        final lineContent = lineMatch.namedGroup('line') ?? '';
        return ' ' * indentation + lineContent;
      }).join('\n');
    });
  });
}
