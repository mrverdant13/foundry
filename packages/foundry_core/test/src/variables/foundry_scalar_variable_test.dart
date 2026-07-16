import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:test/test.dart';

void main() {
  group('FoundryBooleanVariable', () {
    test('derives the default value when no raw value is supplied', () {
      final variable = FoundryBooleanVariable(
        label: 'Use null safety',
        defaultValue: (_) => true,
      );

      final value = variable.resolveValue(
        key: 'use_null_safety',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, isTrue);
    });

    test('preserves a manually supplied raw value over the default', () {
      final variable = FoundryBooleanVariable(
        label: 'Use null safety',
        defaultValue: (_) => true,
      );

      final value = variable.resolveValue(
        key: 'use_null_safety',
        rawValues: const {'use_null_safety': false},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, isFalse);
    });

    test('preserves a dirty false value over the default', () {
      final variable = FoundryBooleanVariable(
        label: 'Use null safety',
        defaultValue: (_) => true,
      );

      final value = variable.resolveValue(
        key: 'use_null_safety',
        rawValues: const {'use_null_safety': false},
        dirtyKeys: const {'use_null_safety'},
        resolvedValues: const {},
      );

      expect(value, isFalse);
    });

    test('throws when a raw value has the wrong type', () {
      const variable = FoundryBooleanVariable(label: 'Use null safety');

      expect(
        () => variable.resolveValue(
          key: 'use_null_safety',
          rawValues: const {'use_null_safety': 'yes'},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type bool for key "use_null_safety" but '
                'found a value of type String.',
          ),
        ),
      );
    });

    test('yields each non-null validator error in order', () {
      final variable = FoundryBooleanVariable(
        label: 'Use null safety',
        validators: [
          (value, _) => value == null ? 'Required.' : null,
          (value, _) => value == false ? 'Must be enabled.' : null,
        ],
      );

      final errors = variable.validate(
        false,
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Must be enabled.']);
    });

    test('throws when validate receives the wrong type', () {
      const variable = FoundryBooleanVariable(label: 'Use null safety');

      expect(
        () => variable.validate(1, SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type bool but found a value of type int.',
          ),
        ),
      );
    });
  });

  group('FoundryIntVariable', () {
    test('derives the default value when no raw value is supplied', () {
      final variable = FoundryIntVariable(
        label: 'Port',
        defaultValue: (_) => 8080,
      );

      final value = variable.resolveValue(
        key: 'port',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 8080);
    });

    test('preserves a manually supplied raw value over the default', () {
      final variable = FoundryIntVariable(
        label: 'Port',
        defaultValue: (_) => 8080,
      );

      final value = variable.resolveValue(
        key: 'port',
        rawValues: const {'port': 3000},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 3000);
    });

    test('throws when a raw value has the wrong type', () {
      const variable = FoundryIntVariable(label: 'Port');

      expect(
        () => variable.resolveValue(
          key: 'port',
          rawValues: const {'port': 3.14},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type int for key "port" but found a value '
                'of type double.',
          ),
        ),
      );
    });

    test('rejects a string raw value as a type mismatch', () {
      const variable = FoundryIntVariable(label: 'Port');

      expect(
        () => variable.resolveValue(
          key: 'port',
          rawValues: const {'port': '8080'},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(isA<FoundryContextException>()),
      );
    });

    test('yields each non-null validator error in order', () {
      final variable = FoundryIntVariable(
        label: 'Port',
        validators: [
          (value, _) => value == null ? 'Required.' : null,
          (value, _) =>
              value != null && value < 1 ? 'Must be at least 1.' : null,
          (value, _) =>
              value != null && value > 65535 ? 'Must be at most 65535.' : null,
        ],
      );

      final errors = variable.validate(
        0,
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Must be at least 1.']);
    });

    test('throws when validate receives the wrong type', () {
      const variable = FoundryIntVariable(label: 'Port');

      expect(
        () => variable.validate(true, SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type int but found a value of type bool.',
          ),
        ),
      );
    });
  });

  group('FoundryDoubleVariable', () {
    test('derives the default value when no raw value is supplied', () {
      final variable = FoundryDoubleVariable(
        label: 'Scale',
        defaultValue: (_) => 1.0,
      );

      final value = variable.resolveValue(
        key: 'scale',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 1.0);
    });

    test('preserves a manually supplied raw value over the default', () {
      final variable = FoundryDoubleVariable(
        label: 'Scale',
        defaultValue: (_) => 1.0,
      );

      final value = variable.resolveValue(
        key: 'scale',
        rawValues: const {'scale': 2.5},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 2.5);
    });

    test('throws when a raw value has the wrong type', () {
      const variable = FoundryDoubleVariable(label: 'Scale');

      expect(
        () => variable.resolveValue(
          key: 'scale',
          rawValues: const {'scale': 2},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type double for key "scale" but found a '
                'value of type int.',
          ),
        ),
      );
    });

    test('yields each non-null validator error in order', () {
      final variable = FoundryDoubleVariable(
        label: 'Scale',
        validators: [
          (value, _) => value == null ? 'Required.' : null,
          (value, _) =>
              value != null && value <= 0 ? 'Must be positive.' : null,
        ],
      );

      final errors = variable.validate(
        0.0,
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Must be positive.']);
    });

    test('throws when validate receives the wrong type', () {
      const variable = FoundryDoubleVariable(label: 'Scale');

      expect(
        () => variable.validate('1.0', SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type double but found a value of type '
                'String.',
          ),
        ),
      );
    });

    test('does not run validators when value has the wrong type', () {
      var validatorCalled = false;
      final variable = FoundryDoubleVariable(
        label: 'Scale',
        validators: [
          (value, _) {
            validatorCalled = true;
            return null;
          },
        ],
      );

      expect(
        () => variable.validate(1, SnapshotFoundryContext(const {})),
        throwsA(isA<FoundryContextException>()),
      );
      expect(validatorCalled, isFalse);
    });
  });
}
