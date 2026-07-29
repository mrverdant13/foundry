import 'dart:io';

import 'package:foundry_core/src/mold/mold_import_exception.dart';
import 'package:foundry_core/src/mold/mold_import_support.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Imports a mold from a git repository into `./<name>/` under
/// [destinationParent] (the process cwd when omitted).
///
/// Clones [gitUrl] into a temporary directory created under [tempParent]
/// (the system temp directory when omitted), optionally descending into
/// [path] when the mold lives in a subdirectory of the repository, then
/// copies it to the destination the same way local import does. The
/// temporary clone is always removed afterward, whether or not the import
/// succeeds.
///
/// When [path] is omitted, the clone is a full shallow clone (`--depth=1`).
/// When [path] is set, Foundry prefers a sparse / partial clone of that
/// subdirectory (`git clone --sparse` plus `git sparse-checkout set`). If
/// sparse checkout is unavailable or fails, it falls back to a full shallow
/// clone and then resolves [path] in the working tree.
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
    await cloneMoldRepository(
      gitUrl: gitUrl,
      destination: tempDirectory,
      path: path,
    );

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

/// Clones [gitUrl] into [destination], optionally limiting the working tree
/// to [path] via sparse checkout.
///
/// Exposed for unit tests that need to inspect the clone before import
/// cleanup. Prefer [importMoldFromGit] for normal callers.
@visibleForTesting
Future<void> cloneMoldRepository({
  required String gitUrl,
  required Directory destination,
  String? path,
}) async {
  final sparsePath = (path == null || path.isEmpty) ? null : path;
  if (sparsePath != null) {
    // Validate escape / absolute paths before any network or disk work.
    _resolveClonePath(destination, sparsePath);
    final sparseSucceeded = await _trySparseClone(
      gitUrl: gitUrl,
      destination: destination,
      path: sparsePath,
    );
    if (sparseSucceeded) {
      return;
    }
    await _clearDirectoryContents(destination);
  }

  await _shallowClone(gitUrl: gitUrl, destination: destination);
}

/// Attempts a sparse / partial clone limited to [path].
///
/// Returns `true` when both `git clone --sparse` and
/// `git sparse-checkout set` succeed. Returns `false` without throwing so
/// callers can fall back to a full shallow clone.
Future<bool> _trySparseClone({
  required String gitUrl,
  required Directory destination,
  required String path,
}) async {
  final cloneResult = await Process.run('git', [
    'clone',
    '--depth=1',
    '--filter=blob:none',
    '--sparse',
    '--quiet',
    gitUrl,
    destination.path,
  ]);
  if (cloneResult.exitCode != 0) {
    return false;
  }

  final sparseResult = await Process.run(
    'git',
    ['sparse-checkout', 'set', '--', path],
    workingDirectory: destination.path,
  );
  return sparseResult.exitCode == 0;
}

Future<void> _shallowClone({
  required String gitUrl,
  required Directory destination,
}) async {
  final cloneResult = await Process.run('git', [
    'clone',
    '--depth=1',
    '--quiet',
    gitUrl,
    destination.path,
  ]);
  if (cloneResult.exitCode != 0) {
    throw MoldImportException(
      'Failed to clone "$gitUrl": ${_processOutput(cloneResult)}',
    );
  }
}

Future<void> _clearDirectoryContents(Directory directory) async {
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
    return;
  }

  await for (final entity in directory.list(followLinks: false)) {
    await entity.delete(recursive: true);
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
