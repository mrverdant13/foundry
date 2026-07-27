import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:path/path.dart' as p;

/// Directory name under the system temp root for cached session helpers.
const moldCastSessionHelperCacheDirName = 'foundry_mold_session_cache';

/// Stamp file written after a successful `dart pub get` for a cache entry.
const moldCastSessionHelperCacheStampFileName = '.foundry_helper_resolve_stamp';

/// Exclusive lock link name held while resolving or running a helper.
const moldCastSessionHelperCacheLockName = '.foundry_helper_resolve_lock';

/// Builds the canonical cache-key string for a mold cast-session helper.
///
/// The key covers the absolute mold path, mold pubspec / lock contents,
/// `foundry_cli` linkage, optional `foundry_core` override, and the running
/// CLI version so a resolve can be reused only when those inputs match.
String buildMoldCastSessionHelperCacheKey({
  required String moldPath,
  required String moldPubspecContents,
  required FoundryCliHelperDependency foundryCli,
  String? moldPubspecLockContents,
  String? foundryCoreOverridePath,
  String cliVersion = foundryCliVersion,
}) {
  final foundryCliLine = switch (foundryCli) {
    FoundryCliPathDependency(:final packageRoot) =>
      'foundry_cli:path:${p.normalize(p.absolute(packageRoot))}',
    FoundryCliHostedDependency(:final version) => 'foundry_cli:hosted:$version',
  };
  final coreOverride = foundryCoreOverridePath == null
      ? 'foundry_core:none'
      : 'foundry_core:path:${p.normalize(p.absolute(foundryCoreOverridePath))}';
  final lockDigest = moldPubspecLockContents == null
      ? 'none'
      : '${sha256.convert(utf8.encode(moldPubspecLockContents))}';

  return [
    'mold:${p.normalize(p.absolute(moldPath))}',
    'cli_version:$cliVersion',
    foundryCliLine,
    coreOverride,
    'pubspec:${sha256.convert(utf8.encode(moldPubspecContents))}',
    'lock:$lockDigest',
  ].join('\n');
}

/// Returns the hex SHA-256 digest used as the cache entry directory name.
String moldCastSessionHelperCacheEntryId(String cacheKey) =>
    sha256.convert(utf8.encode(cacheKey)).toString();

/// Default root directory for cached synthetic helper packages.
Directory defaultMoldCastSessionHelperCacheRoot() => Directory(
      p.join(Directory.systemTemp.path, moldCastSessionHelperCacheDirName),
    );

/// Outcome of preparing a cached (or ephemeral) helper package root.
final class PreparedMoldCastSessionHelper {
  /// Creates a prepared helper root.
  const PreparedMoldCastSessionHelper({
    required this.helperRoot,
    required this.resolveCached,
    required this.ephemeral,
  });

  /// Directory that contains the helper `pubspec.yaml` / bridge / `.dart_tool`.
  final Directory helperRoot;

  /// Whether `dart pub get` can be skipped because a matching stamp exists.
  final bool resolveCached;

  /// Whether [helperRoot] should be deleted after the session finishes.
  final bool ephemeral;
}

/// Reads mold pubspec / lock inputs used to build a helper cache key.
Future<({String pubspec, String? lock})> readMoldCastSessionHelperCacheInputs({
  required Directory moldDirectory,
}) async {
  final pubspecFile = File(p.join(moldDirectory.path, 'pubspec.yaml'));
  final lockFile = File(p.join(moldDirectory.path, 'pubspec.lock'));
  return (
    pubspec: await pubspecFile.readAsString(),
    lock: lockFile.existsSync() ? await lockFile.readAsString() : null,
  );
}

/// Resolves the cache entry directory for [cacheKey] under [cacheRoot].
Directory moldCastSessionHelperCacheEntryDirectory({
  required Directory cacheRoot,
  required String cacheKey,
}) {
  return Directory(
    p.join(cacheRoot.path, moldCastSessionHelperCacheEntryId(cacheKey)),
  );
}

/// Whether [helperRoot] has a matching resolve stamp and package config.
bool isMoldCastSessionHelperResolveCached({
  required Directory helperRoot,
  required String cacheKey,
}) {
  final stampFile = File(
    p.join(helperRoot.path, moldCastSessionHelperCacheStampFileName),
  );
  final packageConfig = File(
    p.join(helperRoot.path, '.dart_tool', 'package_config.json'),
  );
  if (!stampFile.existsSync() || !packageConfig.existsSync()) {
    return false;
  }
  return stampFile.readAsStringSync() == cacheKey;
}

/// Marks [helperRoot] as successfully resolved for [cacheKey].
Future<void> markMoldCastSessionHelperResolveCached({
  required Directory helperRoot,
  required String cacheKey,
}) {
  return File(
    p.join(helperRoot.path, moldCastSessionHelperCacheStampFileName),
  ).writeAsString(cacheKey);
}

/// Clears a successful-resolve stamp so the next launch re-runs `pub get`.
Future<void> clearMoldCastSessionHelperResolveCache({
  required Directory helperRoot,
}) async {
  final stampFile = File(
    p.join(helperRoot.path, moldCastSessionHelperCacheStampFileName),
  );
  if (stampFile.existsSync()) {
    await stampFile.delete();
  }
}

/// Runs [action] while holding an exclusive lock link under [helperRoot].
///
/// Concurrent launches that share the same cache entry serialize on this lock.
/// Stale lock links older than [staleLockTimeout] are removed so a crashed
/// process cannot permanently block the entry.
Future<T> withMoldCastSessionHelperCacheLock<T>({
  required Directory helperRoot,
  required Future<T> Function() action,
  Duration staleLockTimeout = const Duration(minutes: 2),
  Duration retryDelay = const Duration(milliseconds: 50),
  Duration acquireTimeout = const Duration(seconds: 30),
  DateTime Function()? clock,
}) async {
  await helperRoot.create(recursive: true);
  final lockLink = Link(
    p.join(helperRoot.path, moldCastSessionHelperCacheLockName),
  );
  final now = clock ?? DateTime.now;
  final deadline = now().add(acquireTimeout);

  while (true) {
    try {
      // Link.create fails when the path already exists, giving an exclusive
      // acquire without Directory.create(exclusive:), which this SDK lacks.
      await lockLink.create(helperRoot.path);
      break;
    } on FileSystemException {
      if (now().isAfter(deadline)) {
        throw StateError(
          'Timed out waiting for mold cast session helper cache lock at '
          '${lockLink.path}',
        );
      }
      try {
        final stat = lockLink.statSync();
        if (now().difference(stat.modified) > staleLockTimeout) {
          await lockLink.delete();
          continue;
        }
      } on FileSystemException {
        // Lock disappeared between exists and stat; retry create.
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  try {
    return await action();
  } finally {
    if (lockLink.existsSync()) {
      await lockLink.delete();
    }
  }
}

/// Prepares a helper root, optionally reusing a cached resolve.
///
/// When [cacheHelperResolve] is `false`, creates an ephemeral temp directory
/// under [tempParent] (same behavior as the pre-cache launcher).
Future<PreparedMoldCastSessionHelper> prepareMoldCastSessionHelperRoot({
  required String cacheKey,
  required bool cacheHelperResolve,
  Directory? helperCacheRoot,
  Directory? tempParent,
}) async {
  if (!cacheHelperResolve) {
    final helperRoot = await (tempParent ?? Directory.systemTemp).createTemp(
      moldCastSessionHelperTempPrefix,
    );
    return PreparedMoldCastSessionHelper(
      helperRoot: helperRoot,
      resolveCached: false,
      ephemeral: true,
    );
  }

  final cacheRoot = helperCacheRoot ?? defaultMoldCastSessionHelperCacheRoot();
  await cacheRoot.create(recursive: true);
  final helperRoot = moldCastSessionHelperCacheEntryDirectory(
    cacheRoot: cacheRoot,
    cacheKey: cacheKey,
  );
  await helperRoot.create(recursive: true);

  return PreparedMoldCastSessionHelper(
    helperRoot: helperRoot,
    resolveCached: isMoldCastSessionHelperResolveCached(
      helperRoot: helperRoot,
      cacheKey: cacheKey,
    ),
    ephemeral: false,
  );
}
