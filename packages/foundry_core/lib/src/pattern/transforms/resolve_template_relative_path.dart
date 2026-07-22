import 'package:foundry_core/src/pattern/pattern_replacement.dart';
import 'package:foundry_core/src/pattern/transforms/apply_replacements.dart';
import 'package:path/path.dart' as p;

/// Thrown when a pattern path replacement would write outside `template/`.
final class TemplatePathReplacementException implements Exception {
  /// Creates a [TemplatePathReplacementException].
  const TemplatePathReplacementException(this.message);

  /// Human-readable description of why the path was rejected.
  final String message;

  @override
  String toString() => 'TemplatePathReplacementException: $message';
}

/// Applies [replacements] to a pattern-root-relative POSIX path and joins the
/// result under [templateRootPath].
///
/// Rejects absolute resolved paths and any path that would escape
/// [templateRootPath].
String resolveTemplateRelativePath({
  required String relativePosixPath,
  required String templateRootPath,
  required List<PatternReplacement> replacements,
}) {
  final resolvedRelativePath = applyReplacements(
    input: relativePosixPath,
    replacements: replacements,
  );

  if (p.posix.isAbsolute(resolvedRelativePath)) {
    throw TemplatePathReplacementException(
      'Path replacement produced an absolute path ($resolvedRelativePath).',
    );
  }

  final normalizedTemplateRoot = p.normalize(p.absolute(templateRootPath));
  final resolvedPath = p.normalize(
    p.join(
      normalizedTemplateRoot,
      resolvedRelativePath.replaceAll('/', p.separator),
    ),
  );

  if (!p.isWithin(normalizedTemplateRoot, resolvedPath)) {
    throw TemplatePathReplacementException(
      'Path replacement would write outside the template directory '
      '($resolvedRelativePath).',
    );
  }

  return resolvedPath;
}
