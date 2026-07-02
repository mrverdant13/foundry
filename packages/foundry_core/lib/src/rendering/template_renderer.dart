import 'dart:io';

import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/rendering/template_liquid_filters.dart';
import 'package:foundry_core/src/rendering/template_render_exception.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as p;

/// Renders every file under [templateDirectory] to [outputDirectory].
///
/// File contents and path segments are both rendered with Liquid, fed from
/// the entries of [context] (see [SnapshotFoundryContext]). This only
/// renders `template/`; it does not run lifecycle hooks or the rest of a
/// cast.
///
/// When [force] is `false` (the default) and a destination file already
/// exists, a [TemplateRenderException] is thrown before any file is written
/// and the output directory is left untouched. When [force] is `true`,
/// existing files at the rendered destination paths are overwritten; files
/// under [outputDirectory] that do not correspond to a template file are
/// left untouched either way.
///
/// Returns the list of files written, in template-relative path order.
Future<List<File>> renderTemplate({
  required Directory templateDirectory,
  required Directory outputDirectory,
  required SnapshotFoundryContext context,
  bool force = false,
}) async {
  ensureFoundryLiquidFiltersRegistered();

  final resolvedTemplateDirectory = templateDirectory.absolute;
  if (!resolvedTemplateDirectory.existsSync()) {
    throw TemplateRenderException(
      'Template directory "${resolvedTemplateDirectory.path}" does not '
      'exist.',
    );
  }

  final values = context.entries;
  final sourceFiles = Glob('**', recursive: true)
      .listSync(root: resolvedTemplateDirectory.path, followLinks: false)
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final plannedWrites = <_PlannedWrite>[];
  final conflictingPaths = <String>[];

  for (final sourceFile in sourceFiles) {
    final relativeSourcePath = p.relative(
      sourceFile.path,
      from: resolvedTemplateDirectory.path,
    );
    final destinationRelativePath = _renderPathSegments(
      relativeSourcePath,
      values,
    );
    final destinationFile = File(
      p.join(outputDirectory.path, destinationRelativePath),
    );

    if (!force && destinationFile.existsSync()) {
      conflictingPaths.add(destinationFile.path);
      continue;
    }

    final templateContents = await sourceFile.readAsString();
    final renderedContents = Template.parse(
      templateContents,
      data: values,
    ).render();
    plannedWrites.add(_PlannedWrite(destinationFile, renderedContents));
  }

  if (conflictingPaths.isNotEmpty) {
    throw TemplateRenderException(
      'Refusing to overwrite existing file(s) without force: '
      '${conflictingPaths.join(', ')}',
    );
  }

  final writtenFiles = <File>[];
  for (final write in plannedWrites) {
    await write.destination.parent.create(recursive: true);
    await write.destination.writeAsString(write.contents);
    writtenFiles.add(write.destination);
  }

  return writtenFiles;
}

String _renderPathSegments(String relativePath, Map<String, Object?> values) {
  final renderedSegments = p.split(relativePath).map((segment) {
    return Template.parse(segment, data: values).render();
  });
  return p.joinAll(renderedSegments);
}

class _PlannedWrite {
  const _PlannedWrite(this.destination, this.contents);

  final File destination;
  final String contents;
}
