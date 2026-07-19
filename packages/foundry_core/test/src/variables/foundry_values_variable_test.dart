import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:test/test.dart';

FoundryValuesVariable<String> _dependents({
  List<FoundryFieldValidator<String>> itemValidators = const [],
  List<FoundryFieldValidator<List<String>>> validators = const [],
  FoundryDefaultValue<List<String>>? defaultValue,
}) {
  return FoundryValuesVariable<String>(
    label: 'Dependents',
    defaultValue: defaultValue,
    validators: validators,
    item: FoundryStringVariable(
      label: 'Package name',
      validators: itemValidators,
    ),
  );
}

void main() {
  group('FoundryValuesVariable', () {
    test('preserves supplied list order when resolving', () {
      final variable = _dependents();

      final value = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': ['c', 'a', 'b'],
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, ['c', 'a', 'b']);
    });

    test('preserves reorder edits at the model level', () {
      final variable = _dependents();

      final original = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': ['alpha', 'beta', 'gamma'],
        },
        dirtyKeys: const {'dependents'},
        resolvedValues: const {},
      );
      expect(original, ['alpha', 'beta', 'gamma']);

      final reordered = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': ['gamma', 'alpha', 'beta'],
        },
        dirtyKeys: const {'dependents'},
        resolvedValues: const {},
      );
      expect(reordered, ['gamma', 'alpha', 'beta']);
    });

    test('supports add and remove semantics via list edits', () {
      final variable = _dependents();

      final withAdded = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': ['a', 'b', 'c'],
        },
        dirtyKeys: const {'dependents'},
        resolvedValues: const {},
      );
      expect(withAdded, ['a', 'b', 'c']);

      final withRemoved = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': ['a', 'c'],
        },
        dirtyKeys: const {'dependents'},
        resolvedValues: const {},
      );
      expect(withRemoved, ['a', 'c']);
    });

    test('allows an empty list unless validators reject it', () {
      final variable = _dependents();

      final value = variable.resolveValue(
        key: 'dependents',
        rawValues: const {
          'dependents': <String>[],
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, isEmpty);
      expect(
        variable.validate(const <String>[], SnapshotFoundryContext(const {})),
        isEmpty,
      );
    });

    test('derives the default list when no raw value is supplied', () {
      final variable = _dependents(
        defaultValue: (_) => const ['core', 'cli'],
      );

      final value = variable.resolveValue(
        key: 'dependents',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, ['core', 'cli']);
    });

    test('returns null when the values key is dirty and cleared', () {
      final variable = _dependents(
        defaultValue: (_) => const ['fallback'],
      );

      final value = variable.resolveValue(
        key: 'dependents',
        rawValues: const {'dependents': null},
        dirtyKeys: const {'dependents'},
        resolvedValues: const {},
      );

      expect(value, isNull);
    });

    test('throws when a raw value is not a list', () {
      final variable = _dependents();

      expect(
        () => variable.resolveValue(
          key: 'dependents',
          rawValues: const {'dependents': 'not-a-list'},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type List<String> for key "dependents" but '
                'found a value of type String.',
          ),
        ),
      );
    });

    test('throws when a list element has the wrong runtime type', () {
      final variable = _dependents();

      expect(
        () => variable.resolveValue(
          key: 'dependents',
          rawValues: const {
            'dependents': ['ok', 1],
          },
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type String for key "dependents[1]" but '
                'found a value of type int.',
          ),
        ),
      );
    });

    test('throws when a resolved list element is null for a non-nullable T',
        () {
      final variable = _dependents();

      expect(
        () => variable.resolveValue(
          key: 'dependents',
          rawValues: const {
            'dependents': ['ok', null],
          },
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected list elements of type String for key "dependents" but '
                'found a value of type Null.',
          ),
        ),
      );
    });

    test('runs item-kind validation per element with index prefixes', () {
      final variable = _dependents(
        itemValidators: [
          (value, _) =>
              (value == null || value.isEmpty) ? 'Name is required.' : null,
        ],
      );

      final errors = variable.validate(
        const ['foundry_core', '', 'foundry_cli'],
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['[1]: Name is required.']);
    });

    test('runs own validators against the full resolved list', () {
      final variable = _dependents(
        validators: [
          (value, _) => (value != null && value.length > 2)
              ? 'At most two dependents are allowed.'
              : null,
        ],
      );

      final errors = variable.validate(
        const ['a', 'b', 'c'],
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['At most two dependents are allowed.']);
    });

    test('validates null with own validators only', () {
      final variable = _dependents(
        validators: [
          (value, _) => value == null ? 'Dependents are required.' : null,
        ],
      );

      final errors = variable.validate(
        null,
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Dependents are required.']);
    });

    test('throws when validating a non-list value', () {
      final variable = _dependents();

      expect(
        () => variable.validate(42, SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type List<String> but found a value of '
                'type int.',
          ),
        ),
      );
    });

    test('throws when validating a list with a mistyped element', () {
      final variable = _dependents();

      expect(
        () => variable.validate(
          const ['ok', 1],
          SnapshotFoundryContext(const {}),
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected list elements of type String but found a value of '
                'type int.',
          ),
        ),
      );
    });

    test('validates choice item options per element', () {
      final variable = FoundryValuesVariable<String>(
        label: 'Platforms',
        item: FoundrySingleChoiceVariable<String>(
          label: 'Platform',
          options: const ['android', 'ios', 'web'],
          displayLabel: (value) => value,
        ),
      );

      final errors = variable.validate(
        const ['android', 'desktop', 'web'],
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['[1]: Value is not a valid option.']);
    });

    test('resolves and validates nested object item maps', () {
      final variable = FoundryValuesVariable<Map<String, Object?>>(
        label: 'Servers',
        item: FoundryObjectVariable(
          label: 'Server',
          group: FoundryVariableGroup(
            variables: {
              'host': FoundryStringVariable(
                label: 'Host',
                validators: [
                  (value, _) => (value == null || value.isEmpty)
                      ? 'Host is required.'
                      : null,
                ],
              ),
              'port': FoundryIntVariable(
                label: 'Port',
                defaultValue: (_) => 8080,
              ),
            },
          ),
        ),
      );

      final value = variable.resolveValue(
        key: 'servers',
        rawValues: const {
          'servers': [
            {'host': 'api.example.com'},
            {'host': 'cdn.example.com', 'port': 443},
          ],
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, [
        {'host': 'api.example.com', 'port': 8080},
        {'host': 'cdn.example.com', 'port': 443},
      ]);

      final errors = variable.validate(
        const [
          {'host': '', 'port': 80},
        ],
        SnapshotFoundryContext(const {}),
      );
      expect(errors, ['[0]: host: Host is required.']);
    });

    test('round-trips a string list through group evaluation', () {
      final group = FoundryVariableGroup(
        variables: {
          'dependents': _dependents(),
        },
      );

      final evaluation = group.evaluate(
        rawValues: const {
          'dependents': ['foundry_core', 'foundry_cli'],
        },
      );

      expect(evaluation.resolvedValues['dependents'], [
        'foundry_core',
        'foundry_cli',
      ]);

      final validation = group.validate(evaluation);
      expect(validation.isValid, isTrue);
    });
  });
}
