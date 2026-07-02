import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:test/test.dart';

FoundryVariableGroup _buildTestGroup({
  List<FoundryGroupValidator> groupValidators = const [],
}) {
  return FoundryVariableGroup(
    groupValidators: groupValidators,
    variables: {
      'project_type': FoundryStringVariable(
        label: 'Project type',
        validators: [
          (value, _) => (value == null || value.isEmpty) ? 'Required.' : null,
        ],
      ),
      'project_name': FoundryStringVariable(
        label: 'Project name',
        defaultValue: (_) => 'My App',
      ),
      'package_name': FoundryStringVariable(
        label: 'Package name',
        visibleWhen: (context) =>
            context.optionalString('project_type') == 'package',
        defaultValue: (context) {
          final projectName = context.optionalString('project_name') ?? '';
          return projectName.toLowerCase().replaceAll(' ', '_');
        },
        validators: [
          (value, _) => (value == null || value.isEmpty)
              ? 'Package name is required.'
              : null,
        ],
      ),
      'class_name': FoundryStringVariable(
        label: 'Class name',
        defaultValue: (context) => context.requiredString('project_name'),
        enabledWhen: (context) =>
            context.optionalString('project_type') != 'app',
        description: 'The Dart class name used by generated code.',
        placeholder: 'MyApp',
        help: 'Defaults to the project name.',
      ),
    },
  );
}

void main() {
  group('evaluate', () {
    test('recomputes derived defaults for visible fields', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {
          'project_type': 'package',
          'project_name': 'Fancy App',
        },
        dirtyKeys: const {'project_type', 'project_name'},
      );

      expect(evaluation.resolvedValues['project_type'], 'package');
      expect(evaluation.resolvedValues['project_name'], 'Fancy App');
      expect(evaluation.resolvedValues['package_name'], 'fancy_app');
      expect(evaluation.resolvedValues['class_name'], 'Fancy App');
    });

    test('skips a variable whose visibleWhen returns false', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {
          'project_type': 'app',
          'project_name': 'Fancy App',
        },
        dirtyKeys: const {'project_type', 'project_name'},
      );

      expect(evaluation.resolvedValues.containsKey('package_name'), isFalse);
      expect(
        evaluation.entries.any((entry) => entry.key == 'package_name'),
        isFalse,
      );
    });

    test('applies a default value when no raw value is supplied', () {
      final evaluation = _buildTestGroup().evaluate();

      expect(evaluation.resolvedValues['project_name'], 'My App');
    });

    test('preserves a manually edited field during recomputation', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {
          'project_type': 'package',
          'project_name': 'Fancy App',
          'package_name': 'bespoke_pkg',
        },
        dirtyKeys: const {
          'project_type',
          'project_name',
          'package_name',
        },
      );

      expect(evaluation.resolvedValues['package_name'], 'bespoke_pkg');
    });

    test('entries only include visible variables, in declaration order', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {'project_type'},
      );

      expect(
        evaluation.entries.map((entry) => entry.key),
        ['project_type', 'project_name', 'class_name'],
      );
    });

    test('marks a variable read-only when enabledWhen returns false', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {'project_type'},
      );

      final classNameEntry = evaluation.entries.firstWhere(
        (entry) => entry.key == 'class_name',
      );
      expect(classNameEntry.isEnabled, isFalse);
    });

    test('keeps a variable editable when no enabledWhen is set', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'package'},
        dirtyKeys: const {'project_type'},
      );

      final projectNameEntry = evaluation.entries.firstWhere(
        (entry) => entry.key == 'project_name',
      );
      expect(projectNameEntry.isEnabled, isTrue);
    });

    test('keeps a read-only variable visible', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {'project_type'},
      );

      expect(
        evaluation.entries.any((entry) => entry.key == 'class_name'),
        isTrue,
      );
      expect(evaluation.resolvedValues.containsKey('class_name'), isTrue);
    });

    test('surfaces variable metadata on the evaluation entry', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'package'},
        dirtyKeys: const {'project_type'},
      );

      final classNameEntry = evaluation.entries.firstWhere(
        (entry) => entry.key == 'class_name',
      );
      expect(
        classNameEntry.description,
        'The Dart class name used by generated code.',
      );
      expect(classNameEntry.placeholder, 'MyApp');
      expect(classNameEntry.help, 'Defaults to the project name.');
    });

    test('metadata defaults to null when unset', () {
      final evaluation = _buildTestGroup().evaluate(
        rawValues: const {'project_type': 'package'},
        dirtyKeys: const {'project_type'},
      );

      final projectTypeEntry = evaluation.entries.firstWhere(
        (entry) => entry.key == 'project_type',
      );
      expect(projectTypeEntry.description, isNull);
      expect(projectTypeEntry.placeholder, isNull);
      expect(projectTypeEntry.help, isNull);
    });
  });

  group('validate', () {
    test('reports no errors for a fully valid evaluation', () {
      final group = _buildTestGroup();
      final evaluation = group.evaluate(
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {'project_type'},
      );

      final validation = group.validate(evaluation);

      expect(validation.isValid, isTrue);
      expect(validation.fieldErrors, isEmpty);
      expect(validation.groupErrors, isEmpty);
    });

    test('collects field validator errors for invalid visible variables', () {
      final group = _buildTestGroup();
      final evaluation = group.evaluate(
        rawValues: const {'project_type': ''},
        dirtyKeys: const {'project_type'},
      );

      final validation = group.validate(evaluation);

      expect(validation.isValid, isFalse);
      expect(validation.fieldErrors['project_type'], ['Required.']);
    });

    test('does not validate a variable hidden by visibleWhen', () {
      final group = _buildTestGroup();
      final evaluation = group.evaluate(
        rawValues: const {'project_type': 'app'},
        dirtyKeys: const {'project_type', 'package_name'},
      );

      final validation = group.validate(evaluation);

      expect(validation.fieldErrors.containsKey('package_name'), isFalse);
    });

    test('collects group validator errors', () {
      final group = _buildTestGroup(
        groupValidators: [
          (context) {
            if (context.optionalString('project_type') == 'package' &&
                (context.optionalString('package_name') ?? '').isEmpty) {
              return 'package_name is required when project_type is package.';
            }
            return null;
          },
        ],
      );
      final evaluation = group.evaluate(
        rawValues: const {
          'project_type': 'package',
          'package_name': '',
        },
        dirtyKeys: const {'project_type', 'package_name'},
      );

      final validation = group.validate(evaluation);

      expect(validation.isValid, isFalse);
      expect(
        validation.groupErrors,
        ['package_name is required when project_type is package.'],
      );
    });
  });
}
