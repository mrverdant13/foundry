import 'dart:io';

import 'package:foundry_core/src/context/foundry_context.dart';
import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/logging/logger.dart';
import 'package:test/test.dart';

void main() {
  late Directory moldDirectory;
  late Directory outputDirectory;

  setUp(() {
    moldDirectory = Directory('mold');
    outputDirectory = Directory('output');
  });

  FoundryContext buildContext({Map<String, Object?> values = const {}}) {
    return FoundryContext(
      values: values,
      logger: Logger(),
      moldDirectory: moldDirectory,
      outputDirectory: outputDirectory,
    );
  }

  test('extends SnapshotFoundryContext', () {
    expect(buildContext(), isA<SnapshotFoundryContext>());
  });

  test('exposes the hook environment fields', () {
    final logger = Logger();
    final context = FoundryContext(
      logger: logger,
      moldDirectory: moldDirectory,
      outputDirectory: outputDirectory,
    );

    expect(context.logger, same(logger));
    expect(context.moldDirectory, same(moldDirectory));
    expect(context.outputDirectory, same(outputDirectory));
  });

  test('seeds values passed at construction', () {
    final context = buildContext(values: const {'name': 'demo_app'});

    expect(context.requiredString('name'), 'demo_app');
  });

  group('set', () {
    test('adds a new entry', () {
      final context = buildContext()..set('name', 'demo_app');

      expect(context.requiredString('name'), 'demo_app');
    });

    test('replaces an existing entry', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..set('name', 'other_app');

      expect(context.requiredString('name'), 'other_app');
    });
  });

  group('merge', () {
    test('adds all entries from the given map', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..merge(const {'flag': true, 'count': 3});

      expect(context.requiredString('name'), 'demo_app');
      expect(context.requiredBool('flag'), isTrue);
      expect(context.requiredInt('count'), 3);
    });

    test('overwrites existing keys', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..merge(const {'name': 'other_app'});

      expect(context.requiredString('name'), 'other_app');
    });
  });

  group('remove', () {
    test('removes an existing entry', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..remove('name');

      expect(context.contains('name'), isFalse);
    });

    test('is a no-op when the key is absent', () {
      final context = buildContext();

      expect(() => context.remove('missing'), returnsNormally);
      expect(context.contains('missing'), isFalse);
    });
  });

  test('inherited required* accessors still throw as documented', () {
    final context = buildContext();

    expect(
      () => context.requiredString('name'),
      throwsA(isA<FoundryContextException>()),
    );
  });

  group('entries', () {
    test('cannot be mutated to bypass set/merge/remove', () {
      final context = buildContext(values: const {'name': 'demo_app'});

      expect(() => context.entries['name'] = 'other', throwsUnsupportedError);
    });

    test('reflects the latest mutations', () {
      final context = buildContext()..set('name', 'demo_app');

      expect(context.entries, {'name': 'demo_app'});
    });
  });

  group('snapshot', () {
    test('reflects the current values', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..set('flag', true);

      final snapshot = context.snapshot();

      expect(snapshot, isA<SnapshotFoundryContext>());
      expect(snapshot.requiredString('name'), 'demo_app');
      expect(snapshot.requiredBool('flag'), isTrue);
    });

    test('is unaffected by later mutations on the source context', () {
      final context = buildContext(values: const {'name': 'demo_app'});

      final snapshot = context.snapshot();
      context.set('name', 'other_app');

      expect(snapshot.requiredString('name'), 'demo_app');
    });
  });

  group('copyValues', () {
    test('returns a defensive copy of current values', () {
      final context = buildContext(values: const {'name': 'demo_app'})
        ..set('seed', 'from-prepare');

      final values = context.copyValues();
      values['name'] = 'mutated';
      context.set('seed', 'changed');

      expect(context.requiredString('name'), 'demo_app');
      expect(values['seed'], 'from-prepare');
      expect(context.requiredString('seed'), 'changed');
    });
  });
}
