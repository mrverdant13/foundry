import 'dart:io';

import 'package:foundry_core/src/mold/mold_import_exception.dart';
import 'package:foundry_core/src/mold/mold_import_support.dart';
import 'package:path/path.dart' as p;

/// Imports a mold from a git repository into `./<name>/` under
/// [destinationParent] (the process cwd when omitted).
///
/// Shallow-clones [gitUrl] into a temporary directory created under
/// [tempParent] (the system temp directory when omitted), optionally
/// descending into [path] when the mold lives in a subdirectory of the
/// repository, then copies it to the destination the same way local
/// import does. The temporary clone is always removed afterward, whether
/// or not the import succeeds.
///
/// Throws [MoldImportException] when the clone fails, [path] does not
/// exist in the cloned repository, or the destination already exists and
/// [force] is `false`.
Future<Directory> importMoldFromGit({
  required String gitUrl,
  String? path,
  Directory? destinationParent,
  Directory? tempParent,
  bool force = false,
}) async {
  final tempDirectory = await (tempParent ?? Directory.systemTemp).createTemp(
    'foundry_mold_import_',
  );
  try {
    final cloneResult = await Process.run('git', [
      'clone',
      '--depth=1',
      '--quiet',
      gitUrl,
      tempDirectory.path,
    ]);
    if (cloneResult.exitCode != 0) {
      throw MoldImportException(
        'Failed to clone "$gitUrl": ${_processOutput(cloneResult)}',
      );
    }

    final source = (path == null || path.isEmpty)
        ? tempDirectory
        : _resolveClonePath(tempDirectory, path);
    if (!source.existsSync()) {
      throw MoldImportException(
        'Path "$path" was not found in "$gitUrl".',
      );
    }

    return await copyMoldToDestination(
      source: source,
      destinationParent: (destinationParent ?? Directory.current).absolute,
      force: force,
    );
  } finally {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

/// Resolves [path] against [tempDirectory], rejecting values that escape
/// the cloned repository (absolute paths or `..` segments that resolve
/// outside of it).
Directory _resolveClonePath(Directory tempDirectory, String path) {
  if (p.isAbsolute(path)) {
    throw MoldImportException(
      'Path "$path" must be relative to the repository root.',
    );
  }

  final resolved = p.normalize(p.join(tempDirectory.path, path));
  if (!p.isWithin(tempDirectory.path, resolved)) {
    throw MoldImportException(
      'Path "$path" resolves outside of the cloned repository.',
    );
  }

  return Directory(resolved);
}

String _processOutput(ProcessResult result) {
  final output = '${result.stdout}${result.stderr}'.trim();
  return output.isEmpty ? 'git exited with code ${result.exitCode}.' : output;
}
