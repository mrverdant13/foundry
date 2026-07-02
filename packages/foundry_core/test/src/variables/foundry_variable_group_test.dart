import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';
import 'package:test/test.dart';

FoundryVariableGroup _buildTestGroup() {
  return FoundryVariableGroup(
    variables: {
      'project_type': const FoundryStringVariable(
        label: 'Project type',
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
      ),
      'class_name': FoundryStringVariable(
        label: 'Class name',
        defaultValue: (context) => context.requiredString('project_name'),
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
  });
}
