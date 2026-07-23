import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves `partial v <name>` / `partial ^ <name>` blocks in [content].
///
/// Extracts partial payloads into `name.partial` files under
/// [targetAbsolutePath] and replaces each block with
/// `{% render 'name.partial' %}`. Supports C-style, hash, and HTML comment
/// flavors.
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
      File(p.join(targetAbsolutePath, '$partialName.partial'))
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
