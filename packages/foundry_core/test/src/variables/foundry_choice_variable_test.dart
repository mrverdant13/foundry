import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:test/test.dart';

void main() {
  group('FoundrySingleChoiceVariable', () {
    test('requires displayLabel and preserves options order', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value.toUpperCase(),
      );

      expect(variable.options, ['app', 'package']);
      expect(variable.displayLabel('app'), 'APP');
    });

    test('accepts Set options while preserving iteration order', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const {'app', 'package'},
        displayLabel: (value) => value,
      );

      expect(variable.options, ['app', 'package']);
    });

    test('derives the default value when no raw value is supplied', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
        defaultValue: (_) => 'package',
      );

      final value = variable.resolveValue(
        key: 'project_type',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 'package');
    });

    test('preserves a manually supplied raw value over the default', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
        defaultValue: (_) => 'package',
      );

      final value = variable.resolveValue(
        key: 'project_type',
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 'app');
    });

    test('throws when a raw value has the wrong type', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
      );

      expect(
        () => variable.resolveValue(
          key: 'project_type',
          rawValues: const {'project_type': 1},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type String for key "project_type" but '
                'found a value of type int.',
          ),
        ),
      );
    });

    test('rejects a value that is not among the options', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
      );

      final errors = variable.validate(
        'library',
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Value is not a valid option.']);
    });

    test('yields option errors before custom validators', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
        validators: [
          (value, _) => value == 'app' ? 'Apps are disabled.' : null,
        ],
      );

      expect(
        variable.validate('library', SnapshotFoundryContext(const {})),
        ['Value is not a valid option.'],
      );
      expect(
        variable.validate('app', SnapshotFoundryContext(const {})),
        ['Apps are disabled.'],
      );
    });

    test('throws when validate receives the wrong type', () {
      final variable = FoundrySingleChoiceVariable<String>(
        label: 'Project type',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
      );

      expect(
        () => variable.validate(true, SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type String but found a value of type bool.',
          ),
        ),
      );
    });
  });

  group('FoundryMultipleChoiceVariable', () {
    test('requires displayLabel and preserves options order', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      expect(variable.options, ['android', 'ios', 'web']);
      expect(variable.displayLabel('ios'), 'ios');
    });

    test('derives the default value when no raw value is supplied', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
        defaultValue: (_) => const ['web', 'android'],
      );

      final value = variable.resolveValue(
        key: 'platforms',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, ['android', 'web']);
    });

    test('preserves an empty selection over the default', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
        defaultValue: (_) => const ['android'],
      );

      final value = variable.resolveValue(
        key: 'platforms',
        rawValues: const {'platforms': <String>[]},
        dirtyKeys: const {'platforms'},
        resolvedValues: const {},
      );

      expect(value, isEmpty);
    });

    test('normalizes selected values to options declaration order', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      final value = variable.resolveValue(
        key: 'platforms',
        rawValues: const {
          'platforms': ['web', 'android', 'web'],
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, ['android', 'web']);
    });

    test('throws when a raw value is not a list', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      expect(
        () => variable.resolveValue(
          key: 'platforms',
          rawValues: const {'platforms': 'android'},
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type List<String> for key "platforms" but '
                'found a value of type String.',
          ),
        ),
      );
    });

    test('throws when a list element has the wrong type', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      expect(
        () => variable.resolveValue(
          key: 'platforms',
          rawValues: const {
            'platforms': ['android', 1],
          },
          dirtyKeys: const {},
          resolvedValues: const {},
        ),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected list elements of type String for key "platforms" but '
                'found a value of type int.',
          ),
        ),
      );
    });

    test('allows an empty multi selection during validation', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      expect(
        variable.validate(const <String>[], SnapshotFoundryContext(const {})),
        isEmpty,
      );
    });

    test('rejects a selection that includes an invalid option', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      final errors = variable.validate(
        const ['android', 'desktop'],
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Value is not a valid option.']);
    });

    test('keeps invalid options available for validation after resolve', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      final value = variable.resolveValue(
        key: 'platforms',
        rawValues: const {
          'platforms': ['desktop', 'ios'],
        },
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, ['ios', 'desktop']);
      expect(
        variable.validate(value, SnapshotFoundryContext(const {})),
        ['Value is not a valid option.'],
      );
    });

    test('yields each non-null validator error in order', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
        validators: [
          (value, _) => value == null ? 'Required.' : null,
          (value, _) =>
              value != null && value.isEmpty ? 'Pick at least one.' : null,
        ],
      );

      final errors = variable.validate(
        const <String>[],
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Pick at least one.']);
    });

    test('throws when validate receives the wrong type', () {
      final variable = FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      );

      expect(
        () => variable.validate('android', SnapshotFoundryContext(const {})),
        throwsA(
          isA<FoundryContextException>().having(
            (exception) => exception.message,
            'message',
            'Expected a value of type List<String> but found a value of '
                'type String.',
          ),
        ),
      );
    });
  });
}
