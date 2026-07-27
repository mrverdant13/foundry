import 'dart:io';

import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/mold_cast_session_helper_cache.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('buildMoldCastSessionHelperCacheKey', () {
    test('includes mold path, digests, cli linkage, and version', () {
      final key = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/demo_mold',
        moldPubspecContents: 'name: demo\n',
        moldPubspecLockContents: 'packages: {}\n',
        foundryCli:
            const FoundryCliPathDependency('/repo/packages/foundry_cli'),
        foundryCoreOverridePath: '/repo/packages/foundry_core',
        cliVersion: '9.9.9',
      );

      expect(key, contains('mold:'));
      expect(key, contains(p.normalize(p.absolute('/tmp/demo_mold'))));
      expect(key, contains('cli_version:9.9.9'));
      expect(key, contains('foundry_cli:path:'));
      expect(key, contains('foundry_core:path:'));
      expect(key, contains('pubspec:'));
      expect(key, contains('lock:'));
      expect(key, isNot(contains('lock:none')));
    });

    test('treats missing lock and hosted cli distinctly', () {
      final withLock = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/mold',
        moldPubspecContents: 'name: a\n',
        moldPubspecLockContents: 'lock\n',
        foundryCli: const FoundryCliHostedDependency('1.0.0'),
      );
      final withoutLock = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/mold',
        moldPubspecContents: 'name: a\n',
        foundryCli: const FoundryCliHostedDependency('1.0.0'),
      );
      final otherVersion = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/mold',
        moldPubspecContents: 'name: a\n',
        foundryCli: const FoundryCliHostedDependency('1.0.1'),
      );

      expect(withLock, isNot(equals(withoutLock)));
      expect(withoutLock, contains('lock:none'));
      expect(withLock, isNot(equals(otherVersion)));
      expect(withoutLock, contains('foundry_cli:hosted:1.0.0'));
      expect(withoutLock, contains('foundry_core:none'));
      expect(withoutLock, contains('cli_version:$foundryCliVersion'));
    });

    test('changes when mold pubspec contents change', () {
      final before = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/mold',
        moldPubspecContents: 'name: before\n',
        foundryCli: const FoundryCliHostedDependency('1.0.0'),
      );
      final after = buildMoldCastSessionHelperCacheKey(
        moldPath: '/tmp/mold',
        moldPubspecContents: 'name: after\n',
        foundryCli: const FoundryCliHostedDependency('1.0.0'),
      );
      expect(before, isNot(equals(after)));
      expect(
        moldCastSessionHelperCacheEntryId(before),
        isNot(equals(moldCastSessionHelperCacheEntryId(after))),
      );
    });
  });

  group('moldCastSessionHelperCacheEntryId', () {
    test('is a stable hex digest of the cache key', () {
      const key = 'stable-key';
      expect(
        moldCastSessionHelperCacheEntryId(key),
        moldCastSessionHelperCacheEntryId(key),
      );
      expect(
        moldCastSessionHelperCacheEntryId(key),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });
  });

  group('prepareMoldCastSessionHelperRoot', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'foundry_helper_cache_test_',
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('creates an ephemeral temp helper when caching is disabled', () async {
      final prepared = await prepareMoldCastSessionHelperRoot(
        cacheKey: 'key',
        cacheHelperResolve: false,
        tempParent: tempRoot,
      );

      expect(prepared.ephemeral, isTrue);
      expect(prepared.resolveCached, isFalse);
      expect(prepared.helperRoot.existsSync(), isTrue);
      expect(
        p.basename(prepared.helperRoot.path),
        startsWith(moldCastSessionHelperTempPrefix),
      );
      expect(
        p.isWithin(tempRoot.path, prepared.helperRoot.path),
        isTrue,
      );
    });

    test('reuses a stamped cache entry under helperCacheRoot', () async {
      const cacheKey = 'cache-key-v1';
      final cacheRoot = Directory(p.join(tempRoot.path, 'cache'));
      final first = await prepareMoldCastSessionHelperRoot(
        cacheKey: cacheKey,
        cacheHelperResolve: true,
        helperCacheRoot: cacheRoot,
      );
      expect(first.ephemeral, isFalse);
      expect(first.resolveCached, isFalse);

      await Directory(p.join(first.helperRoot.path, '.dart_tool')).create();
      await File(
        p.join(first.helperRoot.path, '.dart_tool', 'package_config.json'),
      ).writeAsString('{}');
      await markMoldCastSessionHelperResolveCached(
        helperRoot: first.helperRoot,
        cacheKey: cacheKey,
      );

      final second = await prepareMoldCastSessionHelperRoot(
        cacheKey: cacheKey,
        cacheHelperResolve: true,
        helperCacheRoot: cacheRoot,
      );
      expect(second.helperRoot.path, first.helperRoot.path);
      expect(second.resolveCached, isTrue);
    });

    test('does not treat a stamp without package_config as cached', () async {
      const cacheKey = 'incomplete';
      final cacheRoot = Directory(p.join(tempRoot.path, 'cache'));
      final prepared = await prepareMoldCastSessionHelperRoot(
        cacheKey: cacheKey,
        cacheHelperResolve: true,
        helperCacheRoot: cacheRoot,
      );
      await markMoldCastSessionHelperResolveCached(
        helperRoot: prepared.helperRoot,
        cacheKey: cacheKey,
      );

      expect(
        isMoldCastSessionHelperResolveCached(
          helperRoot: prepared.helperRoot,
          cacheKey: cacheKey,
        ),
        isFalse,
      );
    });

    test('clearMoldCastSessionHelperResolveCache drops the stamp', () async {
      const cacheKey = 'to-clear';
      final cacheRoot = Directory(p.join(tempRoot.path, 'cache'));
      final prepared = await prepareMoldCastSessionHelperRoot(
        cacheKey: cacheKey,
        cacheHelperResolve: true,
        helperCacheRoot: cacheRoot,
      );
      await Directory(p.join(prepared.helperRoot.path, '.dart_tool')).create();
      await File(
        p.join(prepared.helperRoot.path, '.dart_tool', 'package_config.json'),
      ).writeAsString('{}');
      await markMoldCastSessionHelperResolveCached(
        helperRoot: prepared.helperRoot,
        cacheKey: cacheKey,
      );
      expect(
        isMoldCastSessionHelperResolveCached(
          helperRoot: prepared.helperRoot,
          cacheKey: cacheKey,
        ),
        isTrue,
      );

      await clearMoldCastSessionHelperResolveCache(
        helperRoot: prepared.helperRoot,
      );
      expect(
        isMoldCastSessionHelperResolveCached(
          helperRoot: prepared.helperRoot,
          cacheKey: cacheKey,
        ),
        isFalse,
      );
    });
  });

  group('withMoldCastSessionHelperCacheLock', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'foundry_helper_cache_lock_',
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('serializes concurrent actions on the same helper root', () async {
      final helperRoot = Directory(p.join(tempRoot.path, 'entry'))
        ..createSync();
      final order = <String>[];

      final first = withMoldCastSessionHelperCacheLock(
        helperRoot: helperRoot,
        retryDelay: const Duration(milliseconds: 10),
        action: () async {
          order.add('first-enter');
          await Future<void>.delayed(const Duration(milliseconds: 80));
          order.add('first-exit');
          return 1;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = withMoldCastSessionHelperCacheLock(
        helperRoot: helperRoot,
        retryDelay: const Duration(milliseconds: 10),
        action: () async {
          order
            ..add('second-enter')
            ..add('second-exit');
          return 2;
        },
      );

      expect(await Future.wait([first, second]), [1, 2]);
      expect(order, [
        'first-enter',
        'first-exit',
        'second-enter',
        'second-exit',
      ]);
    });

    test('removes a stale lock link and continues', () async {
      final helperRoot = Directory(p.join(tempRoot.path, 'entry'))
        ..createSync();
      final lockLink = Link(
        p.join(helperRoot.path, moldCastSessionHelperCacheLockName),
      )..createSync(helperRoot.path);
      // Zero stale timeout so any existing lock is treated as stale.
      final value = await withMoldCastSessionHelperCacheLock(
        helperRoot: helperRoot,
        staleLockTimeout: Duration.zero,
        retryDelay: const Duration(milliseconds: 5),
        action: () async => 'ok',
      );
      expect(value, 'ok');
      expect(lockLink.existsSync(), isFalse);
    });
  });

  group('defaultMoldCastSessionHelperCacheRoot', () {
    test('lives under the system temp directory', () {
      final root = defaultMoldCastSessionHelperCacheRoot();
      expect(
        p.equals(
          p.normalize(root.parent.path),
          p.normalize(Directory.systemTemp.path),
        ),
        isTrue,
      );
      expect(p.basename(root.path), moldCastSessionHelperCacheDirName);
    });
  });
}
