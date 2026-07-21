import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Whether [relativePosix] matches any of [ignoreGlobs].
///
/// Globs are POSIX paths relative to a pattern root. Patterns that start with
/// `**/` also match at the root (for example `**/*.tmp` matches `scratch.tmp`).
bool isPatternPathIgnored(String relativePosix, List<String> ignoreGlobs) {
  if (ignoreGlobs.isEmpty) {
    return false;
  }
  return _isIgnored(
    relativePosix,
    compilePatternIgnoreMatchers(ignoreGlobs),
  );
}

/// Precompiled ignore matchers for a pattern directory.
///
/// Patterns that start with `**/` also keep a stripped form so root-level
/// paths match (`**/*.tmp` matches `scratch.tmp`) without rebuilding [Glob]s
/// per file.
final class PatternIgnoreMatcher {
  /// Creates a [PatternIgnoreMatcher].
  const PatternIgnoreMatcher({
    required this.primary,
    this.withoutPrefix,
  });

  /// Primary glob as authored in the pattern marker.
  final Glob primary;

  /// Optional glob with a leading `**/` stripped for root-level matches.
  final Glob? withoutPrefix;

  /// Whether [relativePosix] matches this ignore rule.
  bool matches(String relativePosix) {
    if (primary.matches(relativePosix)) {
      return true;
    }
    return withoutPrefix?.matches(relativePosix) ?? false;
  }
}

/// Compiles [ignoreGlobs] into reusable [PatternIgnoreMatcher]s.
List<PatternIgnoreMatcher> compilePatternIgnoreMatchers(
  List<String> ignoreGlobs,
) {
  return [
    for (final pattern in ignoreGlobs)
      PatternIgnoreMatcher(
        primary: Glob(pattern, context: p.posix),
        withoutPrefix: pattern.startsWith('**/')
            ? Glob(pattern.substring(3), context: p.posix)
            : null,
      ),
  ];
}

bool _isIgnored(String relativePosix, List<PatternIgnoreMatcher> matchers) {
  for (final matcher in matchers) {
    if (matcher.matches(relativePosix)) {
      return true;
    }
  }
  return false;
}
