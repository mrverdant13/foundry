import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:test/test.dart';

final class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}

void main() {
  group('contains', () {
    test('is true when the key is present, even with a null value', () {
      final context = SnapshotFoundryContext(const {'name': null});

      expect(context.contains('name'), isTrue);
    });

    test('is false when the key is absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(context.contains('name'), isFalse);
    });
  });

  group('optionalString', () {
    test('returns the value when present', () {
      final context = SnapshotFoundryContext(const {'name': 'demo_app'});

      expect(context.optionalString('name'), 'demo_app');
    });

    test('returns null when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(context.optionalString('name'), isNull);
    });

    test('returns null when the value is null', () {
      final context = SnapshotFoundryContext(const {'name': null});

      expect(context.optionalString('name'), isNull);
    });

    test('throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'name': 1});

      expect(
        () => context.optionalString('name'),
        throwsA(
          isA<FoundryContextException>().having(
            (error) => error.message,
            'message',
            contains('String'),
          ),
        ),
      );
    });
  });

  group('requiredString', () {
    test('returns the value when present', () {
      final context = SnapshotFoundryContext(const {'name': 'demo_app'});

      expect(context.requiredString('name'), 'demo_app');
    });

    test('throws when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(
        () => context.requiredString('name'),
        throwsA(
          isA<FoundryContextException>().having(
            (error) => error.message,
            'message',
            contains('Missing required value for key "name"'),
          ),
        ),
      );
    });

    test('throws when the value is null', () {
      final context = SnapshotFoundryContext(const {'name': null});

      expect(
        () => context.requiredString('name'),
        throwsA(isA<FoundryContextException>()),
      );
    });

    test('throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'name': 1});

      expect(
        () => context.requiredString('name'),
        throwsA(
          isA<FoundryContextException>().having(
            (error) => error.message,
            'message',
            contains('Expected a value of type String for key "name"'),
          ),
        ),
      );
    });
  });

  group('optionalBool / requiredBool', () {
    test('optionalBool returns the value when present', () {
      final context = SnapshotFoundryContext(const {'flag': true});

      expect(context.optionalBool('flag'), isTrue);
    });

    test('optionalBool returns null when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(context.optionalBool('flag'), isNull);
    });

    test('optionalBool throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'flag': 'yes'});

      expect(
        () => context.optionalBool('flag'),
        throwsA(isA<FoundryContextException>()),
      );
    });

    test('requiredBool returns the value when present', () {
      final context = SnapshotFoundryContext(const {'flag': false});

      expect(context.requiredBool('flag'), isFalse);
    });

    test('requiredBool throws when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(
        () => context.requiredBool('flag'),
        throwsA(isA<FoundryContextException>()),
      );
    });
  });

  group('optionalInt / requiredInt', () {
    test('optionalInt returns the value when present', () {
      final context = SnapshotFoundryContext(const {'count': 3});

      expect(context.optionalInt('count'), 3);
    });

    test('optionalInt returns null when the value is null', () {
      final context = SnapshotFoundryContext(const {'count': null});

      expect(context.optionalInt('count'), isNull);
    });

    test('optionalInt throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'count': '3'});

      expect(
        () => context.optionalInt('count'),
        throwsA(isA<FoundryContextException>()),
      );
    });

    test('requiredInt returns the value when present', () {
      final context = SnapshotFoundryContext(const {'count': 3});

      expect(context.requiredInt('count'), 3);
    });

    test('requiredInt throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'count': '3'});

      expect(
        () => context.requiredInt('count'),
        throwsA(isA<FoundryContextException>()),
      );
    });
  });

  group('optionalDouble / requiredDouble', () {
    test('optionalDouble returns the value when present', () {
      final context = SnapshotFoundryContext(const {'ratio': 1.5});

      expect(context.optionalDouble('ratio'), 1.5);
    });

    test('optionalDouble returns null when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(context.optionalDouble('ratio'), isNull);
    });

    test('optionalDouble throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'ratio': 1});

      expect(
        () => context.optionalDouble('ratio'),
        throwsA(isA<FoundryContextException>()),
      );
    });

    test('requiredDouble returns the value when present', () {
      final context = SnapshotFoundryContext(const {'ratio': 1.5});

      expect(context.requiredDouble('ratio'), 1.5);
    });

    test('requiredDouble throws when the value is null', () {
      final context = SnapshotFoundryContext(const {'ratio': null});

      expect(
        () => context.requiredDouble('ratio'),
        throwsA(isA<FoundryContextException>()),
      );
    });
  });

  group('optional<T> / required<T>', () {
    test('optional<T> returns a custom seeded object', () {
      final context = SnapshotFoundryContext(const {'point': _Point(1, 2)});

      final point = context.optional<_Point>('point');

      expect(point?.x, 1);
      expect(point?.y, 2);
    });

    test('optional<T> returns null when absent', () {
      final context = SnapshotFoundryContext(const {});

      expect(context.optional<_Point>('point'), isNull);
    });

    test('required<T> returns a custom seeded object', () {
      final context = SnapshotFoundryContext(const {'point': _Point(1, 2)});

      final point = context.required<_Point>('point');

      expect(point.x, 1);
      expect(point.y, 2);
    });

    test('required<T> throws when the value has the wrong type', () {
      final context = SnapshotFoundryContext(const {'point': 'not a point'});

      expect(
        () => context.required<_Point>('point'),
        throwsA(
          isA<FoundryContextException>().having(
            (error) => error.message,
            'message',
            contains('_Point'),
          ),
        ),
      );
    });
  });

  group('entries', () {
    test('exposes an unmodifiable snapshot of the current values', () {
      final context = SnapshotFoundryContext(const {'name': 'demo_app'});

      expect(context.entries, {'name': 'demo_app'});
      expect(() => context.entries['name'] = 'other', throwsUnsupportedError);
    });

    test('is not affected by later mutations of the source map', () {
      final source = {'name': 'demo_app'};
      final context = SnapshotFoundryContext(source);

      source['name'] = 'mutated';

      expect(context.entries, {'name': 'demo_app'});
    });
  });
}
