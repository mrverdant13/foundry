import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves `partial v <name>` / `partial ^ <name>` blocks in [content].
///
/// Extracts partial payloads into `name.partial` files under
/// [targetAbsolutePath] and replaces each block with
/// `{% render 'name.partial' %}`. Supports C-style, hash, and HTML comment
/// flavors.
///
/// Partial names form a single namespace under [targetAbsolutePath] (typically
/// the mold `template/` root). Writing the same name with identical content is
/// allowed; a different payload for an existing name throws [FormatException].
///
/// Surrounding whitespace in markers is ignored. Partial names must not be
/// empty, `.`, `..`, contain path separators, or include characters that are
/// invalid in filenames. Invalid names throw [FormatException].
String applyPartials({
  required String content,
  required String targetAbsolutePath,
}) {
  const partialPatterns = [
    r'\/\*partial v\s+(?<partialName>[^\s*/]+)\s*\*\/(?<partialPayload>.*?)\/\*partial \^ \s*\k<partialName>\s*\*\/',
    r'#partial v\s+(?<partialName>[^\s#]+)\s*#(?<partialPayload>.*?)#partial \^ \s*\k<partialName>\s*#',
    r'<!--partial v\s+(?<partialName>[^\s>-]+)\s*-->(?<partialPayload>.*?)<!--partial \^ \s*\k<partialName>\s*-->',
  ];

  return partialPatterns.fold(content, (resolved, pattern) {
    final regex = RegExp(pattern, dotAll: true);
    return resolved.replaceAllMapped(regex, (match) {
      match as RegExpMatch;
      final rawPartialName = match.namedGroup('partialName') ?? '';
      final partialName = _validatedPartialName(rawPartialName);
      final partialPayload = match.namedGroup('partialPayload') ?? '';
      if (targetAbsolutePath.isEmpty) {
        throw ArgumentError(
          'targetAbsolutePath is required when content contains partial '
          'annotations.',
        );
      }
      final partialFile = File(
        p.join(targetAbsolutePath, '$partialName.partial'),
      );
      if (partialFile.existsSync()) {
        final existing = partialFile.readAsStringSync();
        if (existing != partialPayload) {
          throw FormatException(
            'Partial name "$partialName" collides with an existing '
            '"$partialName.partial" that has different content.',
          );
        }
      }
      partialFile
        ..createSync(recursive: true)
        ..writeAsStringSync(partialPayload);
      return "{% render '$partialName.partial' %}";
    });
  });
}

final _invalidPartialNameCharacters = RegExp(r'[\r\n<>:"|?*]');

String _validatedPartialName(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains(r'\') ||
      _invalidPartialNameCharacters.hasMatch(name)) {
    throw FormatException(
      'Invalid partial name "$rawName": must be non-empty and must not be '
      '".", "..", contain path separators, or include filename-invalid '
      'characters.',
    );
  }
  return name;
}
