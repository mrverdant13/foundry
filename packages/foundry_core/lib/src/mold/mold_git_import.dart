import 'dart:io';

import 'package:foundry_core/src/mold/mold_import_exception.dart';
import 'package:foundry_core/src/mold/mold_import_support.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Runs `git` with [arguments], optionally in [workingDirectory].
///
/// Exposed so unit tests can simulate sparse-checkout failures without
/// depending on a specific Git capability matrix.
@visibleForTesting
typedef MoldGitRunner = Future<ProcessResult> Function(
  List<String> arguments, {
  String? workingDirectory,
});

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
/// When [gitRunner] is omitted, invokes the real `git` executable. Prefer
/// [importMoldFromGit] for normal callers.
///
/// Exposed for unit tests that need to inspect the clone before import
/// cleanup or simulate Git failures.
@visibleForTesting
Future<void> cloneMoldRepository({
  required String gitUrl,
  required Directory destination,
  String? path,
  MoldGitRunner? gitRunner,
}) async {
  final sparsePath = (path == null || path.isEmpty) ? null : path;
  if (sparsePath != null) {
    // Validate escape / absolute paths before any network or disk work.
    _resolveClonePath(destination, sparsePath);
    final sparseSucceeded = await _trySparseClone(
      gitUrl: gitUrl,
      destination: destination,
      path: sparsePath,
      gitRunner: gitRunner,
    );
    if (sparseSucceeded) {
      return;
    }
    await clearMoldImportDirectory(destination);
  }

  await _shallowClone(
    gitUrl: gitUrl,
    destination: destination,
    gitRunner: gitRunner,
  );
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
  MoldGitRunner? gitRunner,
}) async {
  final cloneResult = await _runGit(
    [
      'clone',
      '--depth=1',
      '--filter=blob:none',
      '--sparse',
      '--quiet',
      gitUrl,
      destination.path,
    ],
    gitRunner: gitRunner,
  );
  if (cloneResult.exitCode != 0) {
    return false;
  }

  final sparseResult = await _runGit(
    ['sparse-checkout', 'set', '--', path],
    workingDirectory: destination.path,
    gitRunner: gitRunner,
  );
  return sparseResult.exitCode == 0;
}

Future<void> _shallowClone({
  required String gitUrl,
  required Directory destination,
  MoldGitRunner? gitRunner,
}) async {
  final cloneResult = await _runGit(
    [
      'clone',
      '--depth=1',
      '--quiet',
      gitUrl,
      destination.path,
    ],
    gitRunner: gitRunner,
  );
  if (cloneResult.exitCode != 0) {
    throw MoldImportException(
      'Failed to clone "$gitUrl": ${describeGitCloneFailure(cloneResult)}',
    );
  }
}

Future<ProcessResult> _runGit(
  List<String> arguments, {
  String? workingDirectory,
  MoldGitRunner? gitRunner,
}) {
  if (gitRunner != null) {
    return gitRunner(arguments, workingDirectory: workingDirectory);
  }
  return Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
  );
}

/// Clears [directory] so a full shallow clone can reuse it after a failed
/// sparse checkout attempt.
///
/// When [directory] is missing, creates an empty directory. When it exists,
/// deletes its contents (including a partial `.git`) but keeps the directory
/// itself so `git clone` can write into it.
///
/// Exposed for unit tests covering the sparse-checkout fallback cleanup.
@visibleForTesting
Future<void> clearMoldImportDirectory(Directory directory) async {
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

/// Builds the error detail used when a `git clone` exits non-zero.
///
/// Exposed for unit tests covering empty and non-empty process output.
@visibleForTesting
String describeGitCloneFailure(ProcessResult result) {
  final output = '${result.stdout}${result.stderr}'.trim();
  return output.isEmpty ? 'git exited with code ${result.exitCode}.' : output;
}
