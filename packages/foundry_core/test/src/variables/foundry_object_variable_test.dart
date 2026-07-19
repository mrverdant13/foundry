import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:test/test.dart';

FoundryObjectVariable _publishSettings({
  List<FoundryGroupValidator> nestedGroupValidators = const [],
  List<FoundryFieldValidator<Map<String, Object?>>> validators = const [],
  FoundryDefaultValue<Map<String, Object?>>? defaultValue,
}) {
  return FoundryObjectVariable(
    label: 'Publish settings',
    defaultValue: defaultValue,
    validators: validators,
    group: FoundryVariableGroup(
      groupValidators: nestedGroupValidators,
      variables: {
        'host': FoundryStringVariable(
          label: 'Host',
          defaultValue: (_) => 'localhost',
          validators: [
            (value, _) =>
                (value == null || value.isEmpty) ? 'Host is required.' : null,
          ],
        ),
        'port': FoundryIntVariable(
          label: 'Port',
          defaultValue: (_) => 8080,
          visibleWhen: (context) => context.optionalString('host') != 'hidden',
          validators: [
            (value, _) =>
                (value == null || value <= 0) ? 'Port must be positive.' : null,
          ],
        ),
        'secure': FoundryBooleanVariable(
          label: 'Secure',
          defaultValue: (_) => true,
          enabledWhen: (context) => context.optionalString('host') != 'locked',
        ),
      },
    ),
  );
}

void main() {
  group('FoundryObjectVariable', () {
    test('applies nested defaults when no raw map is supplied', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'localhost',
        'port': 8080,
        'secure': true,
      });
    });

    test('evaluates a supplied JSON-shaped map through the nested group', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {
          'publish': {
            'host': 'api.example.com',
            'port': 443,
            'secure': false,
          },
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'api.example.com',
        'port': 443,
        'secure': false,
      });
    });

    test('fills nested defaults for keys missing from a raw map', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {
          'publish': {
            'host': 'api.example.com',
          },
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'api.example.com',
        'port': 8080,
        'secure': true,
      });
    });

    test('uses a parent defaultValue as nested raw seed', () {
      final variable = _publishSettings(
        defaultValue: (_) => const {
          'host': 'from-parent',
        },
      );

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'from-parent',
        'port': 8080,
        'secure': true,
      });
    });

    test('honors nested visibleWhen when resolving', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {
          'publish': {
            'host': 'hidden',
          },
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'hidden',
        'secure': true,
      });
      expect((value! as Map).containsKey('port'), isFalse);
    });

    test('returns null when the object key is dirty and cleared', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {'publish': null},
        dirtyKeys: const {'publish'},
        resolvedValues: const {},
      );

      expect(value, isNull);
    });

    test('preserves nested null when a nested key is present in raw', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {
          'publish': {
            'host': 'api.example.com',
            'port': null,
          },
        },
        dirtyKeys: const {'publish'},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'api.example.com',
        'port': null,
        'secure': true,
      });
    });

    test('preserves nested null during validate instead of re-defaulting', () {
      final variable = _publishSettings();

      final errors = variable.validate(
        const {
          'host': 'api.example.com',
          'port': null,
        },
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['port: Port must be positive.']);
    });

    test('recomputes nested defaults for keys omitted from nested raw', () {
      final variable = FoundryObjectVariable(
        label: 'Publish settings',
        group: FoundryVariableGroup(
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => 'localhost',
            ),
            'port': FoundryIntVariable(
              label: 'Port',
              defaultValue: (context) =>
                  context.optionalString('host') == 'api.example.com'
                      ? 443
                      : 8080,
            ),
          },
        ),
      );

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: const {
          'publish': {
            'host': 'api.example.com',
          },
        },
        dirtyKeys: const {'publish'},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'api.example.com',
        'port': 443,
      });
    });

    test('throws when a raw value is not a map', () {
      final variable = _publishSettings();

      expect(
        () => variable.resolveValue(
          key: 'publish',
          rawValues: const {'publish': 'not-a-map'},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type Map<String, Object?> for key '
                '"publish" but found a value of type String.',
          ),
        ),
      );
    });

    test('accepts a non-string-keyed map by coercing keys to strings', () {
      final variable = _publishSettings();

      final value = variable.resolveValue(
        key: 'publish',
        rawValues: {
          'publish': <Object?, Object?>{
            'host': 'coerced',
            'port': 9,
          },
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, {
        'host': 'coerced',
        'port': 9,
        'secure': true,
      });
    });

    test('flattens nested field and group validation errors', () {
      final variable = _publishSettings(
        nestedGroupValidators: [
          (context) {
            final host = context.optionalString('host');
            final port = context.optionalInt('port');
            if (host == 'localhost' && port == 80) {
              return 'Localhost cannot use port 80.';
            }
            return null;
          },
        ],
      );

      final errors = variable.validate(
        const {
          'host': 'localhost',
          'port': 80,
        },
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Localhost cannot use port 80.']);
    });

    test('flattens nested field validator errors with key prefixes', () {
      final variable = _publishSettings();

      final errors = variable.validate(
        const {
          'host': '',
          'port': 0,
        },
        SnapshotFoundryContext(const {}),
      );

      expect(
        errors,
        [
          'host: Host is required.',
          'port: Port must be positive.',
        ],
      );
    });

    test('runs own validators against the nested resolved map', () {
      final variable = _publishSettings(
        validators: [
          (value, _) {
            final host = value?['host'];
            if (host == 'blocked') {
              return 'Host is blocked.';
            }
            return null;
          },
        ],
      );

      final errors = variable.validate(
        const {
          'host': 'blocked',
          'port': 443,
        },
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Host is blocked.']);
    });

    test('validates null with own validators only', () {
      final variable = _publishSettings(
        validators: [
          (value, _) => value == null ? 'Publish settings are required.' : null,
        ],
      );

      final errors = variable.validate(
        null,
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Publish settings are required.']);
    });

    test('throws when validating a non-map value', () {
      final variable = _publishSettings();

      expect(
        () => variable.validate(42, SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type Map<String, Object?> but found a '
                'value of type int.',
          ),
        ),
      );
    });

    test('round-trips a JSON-shaped map through group evaluation', () {
      final group = FoundryVariableGroup(
        variables: {
          'publish': _publishSettings(),
        },
      );

      final evaluation = group.evaluate(
        rawValues: const {
          'publish': {
            'host': 'api.example.com',
            'port': 443,
            'secure': true,
          },
        },
      );

      expect(evaluation.resolvedValues['publish'], {
        'host': 'api.example.com',
        'port': 443,
        'secure': true,
      });

      final validation = group.validate(evaluation);
      expect(validation.isValid, isTrue);
    });
  });
}
