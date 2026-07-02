import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:test/test.dart';

void main() {
  group('isVisible', () {
    test('is true when no visibleWhen callback is set', () {
      const variable = FoundryStringVariable(label: 'Project name');

      expect(variable.isVisible(SnapshotFoundryContext(const {})), isTrue);
    });

    test('reflects the visibleWhen callback result', () {
      final variable = FoundryStringVariable(
        label: 'Package name',
        visibleWhen: (context) =>
            context.requiredString('project_type') == 'package',
      );

      expect(
        variable.isVisible(
          SnapshotFoundryContext(const {'project_type': 'package'}),
        ),
        isTrue,
      );
      expect(
        variable.isVisible(
          SnapshotFoundryContext(const {'project_type': 'app'}),
        ),
        isFalse,
      );
    });

    test('receives a SnapshotFoundryContext, not a mutable one', () {
      SnapshotFoundryContext? received;
      FoundryStringVariable(
        label: 'Package name',
        visibleWhen: (context) {
          received = context;
          return true;
        },
      ).isVisible(SnapshotFoundryContext(const {}));

      expect(
        received,
        isA<SnapshotFoundryContext>().having(
          (context) => context.runtimeType,
          'runtimeType',
          SnapshotFoundryContext,
        ),
      );
    });
  });

  group('resolveValue', () {
    test('derives the default value when no raw value is supplied', () {
      final variable = FoundryStringVariable(
        label: 'Project name',
        defaultValue: (_) => 'My App',
      );

      final value = variable.resolveValue(
        key: 'project_name',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 'My App');
    });

    test('returns null when no raw value and no default are available', () {
      const variable = FoundryStringVariable(label: 'Project name');

      final value = variable.resolveValue(
        key: 'project_name',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, isNull);
    });

    test('preserves a manually supplied raw value over the default', () {
      final variable = FoundryStringVariable(
        label: 'Project name',
        defaultValue: (_) => 'My App',
      );

      final value = variable.resolveValue(
        key: 'project_name',
        rawValues: const {'project_name': 'Custom App'},
        dirtyKeys: const {},
        resolvedValues: const {},
      );

      expect(value, 'Custom App');
    });

    test('preserves a dirty key even when its raw value is falsy', () {
      final variable = FoundryStringVariable(
        label: 'Package name',
        defaultValue: (_) => 'derived_name',
      );

      final value = variable.resolveValue(
        key: 'package_name',
        rawValues: const {'package_name': ''},
        dirtyKeys: const {'package_name'},
        resolvedValues: const {},
      );

      expect(value, '');
    });

    test('derives the default from already resolved values', () {
      final variable = FoundryStringVariable(
        label: 'Class name',
        defaultValue: (context) => context.requiredString('project_name'),
      );

      final value = variable.resolveValue(
        key: 'class_name',
        rawValues: const {},
        dirtyKeys: const {},
        resolvedValues: const {'project_name': 'My App'},
      );

      expect(value, 'My App');
    });
  });

  group('validate', () {
    test('yields no errors when there are no validators', () {
      const variable = FoundryStringVariable(label: 'Project name');

      final errors = variable.validate(
        'value',
        SnapshotFoundryContext(const {}),
      );

      expect(errors, isEmpty);
    });

    test('yields each non-null validator error in order', () {
      final variable = FoundryStringVariable(
        label: 'Project name',
        validators: [
          (value, _) => value == null || value.isEmpty ? 'Required.' : null,
          (value, _) => (value?.length ?? 0) > 3 ? null : 'Too short.',
        ],
      );

      final errors = variable.validate(
        '',
        SnapshotFoundryContext(const {}),
      );

      expect(errors, ['Required.', 'Too short.']);
    });

    test('validators receive a SnapshotFoundryContext', () {
      SnapshotFoundryContext? received;
      FoundryStringVariable(
        label: 'Project name',
        validators: [
          (value, context) {
            received = context;
            return null;
          },
        ],
      ).validate('value', SnapshotFoundryContext(const {}));

      expect(
        received,
        isA<SnapshotFoundryContext>().having(
          (context) => context.runtimeType,
          'runtimeType',
          SnapshotFoundryContext,
        ),
      );
    });
  });
}
