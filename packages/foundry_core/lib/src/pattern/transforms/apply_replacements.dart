import 'package:foundry_core/src/pattern/pattern_replacement.dart';

/// Applies a single [replacement] to [input], interpolating `${n}` capture
/// groups from [PatternReplacement.to].
///
/// Capture references use the form `${n}` (not `$n`). Missing groups resolve
/// to an empty string.
String applyReplacement({
  required String input,
  required PatternReplacement replacement,
}) {
  final toGroupMatches = RegExp(r'\${(\d+)}').allMatches(replacement.to);
  final seenGroups = <int>{};
  final toGroups = [
    for (final groupMatch in toGroupMatches)
      if (seenGroups.add(int.parse(groupMatch.group(1)!)))
        int.parse(groupMatch.group(1)!),
  ];

  return input.replaceAllMapped(replacement.from, (match) {
    match as RegExpMatch;
    return toGroups.fold(
      replacement.to,
      (resolved, group) {
        final capture = group <= match.groupCount ? match.group(group) : null;
        return resolved.replaceAll('\${$group}', capture ?? '');
      },
    );
  });
}

/// Applies [replacements] sequentially to [input] (file paths or contents).
///
/// Order matters: each replacement sees the output of the previous one.
String applyReplacements({
  required String input,
  required List<PatternReplacement> replacements,
}) {
  return replacements.fold(
    input,
    (resolved, replacement) => applyReplacement(
      input: resolved,
      replacement: replacement,
    ),
  );
}
