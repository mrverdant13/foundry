import 'package:path/path.dart' as p;

/// Formats [path] for user-facing CLI messages relative to [cwd] when possible.
///
/// When [path] resolves under [cwd], returns a `./…` (or `.\…`) relative form.
/// Otherwise returns the normalized absolute path.
String formatDisplayPath(String path, {required String cwd}) {
  final absoluteCwd = p.normalize(p.absolute(cwd));
  final absolutePath = p.normalize(
    p.isAbsolute(path) ? path : p.join(absoluteCwd, path),
  );

  final relative = p.relative(absolutePath, from: absoluteCwd);
  if (relative == '..' ||
      relative.startsWith('..${p.separator}') ||
      p.isAbsolute(relative)) {
    return absolutePath;
  }

  if (relative == '.') {
    return '.${p.separator}';
  }

  return '.${p.separator}$relative';
}
