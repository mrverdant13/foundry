import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_variables_payload.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:test/test.dart';

void main() {
  group('deserializeMoldVariableGroup', () {
    test('deserializes string variables', () {
      final group = deserializeMoldVariableGroup({
        'variables': {
          'project_name': {
            'kind': 'string',
            'label': 'Project name',
          },
        },
      });

      expect(group.variables, hasLength(1));
      expect(group.variables['project_name']?.label, 'Project name');
    });

    test('deserializes boolean, int, and double variables', () {
      final group = deserializeMoldVariableGroup({
        'variables': {
          'use_null_safety': {
            'kind': 'boolean',
            'label': 'Use null safety',
          },
          'port': {
            'kind': 'int',
            'label': 'Port',
          },
          'scale': {
            'kind': 'double',
            'label': 'Scale',
          },
        },
      });

      expect(group.variables, hasLength(3));
      expect(
        group.variables['use_null_safety'],
        isA<FoundryBooleanVariable>().having(
          (variable) => variable.label,
          'label',
          'Use null safety',
        ),
      );
      expect(
        group.variables['port'],
        isA<FoundryIntVariable>().having(
          (variable) => variable.label,
          'label',
          'Port',
        ),
      );
      expect(
        group.variables['scale'],
        isA<FoundryDoubleVariable>().having(
          (variable) => variable.label,
          'label',
          'Scale',
        ),
      );
    });

    test('deserializes single and multiple choice variables', () {
      final group = deserializeMoldVariableGroup({
        'variables': {
          'project_type': {
            'kind': 'single-choice',
            'label': 'Project type',
            'options': ['app', 'package'],
          },
          'platforms': {
            'kind': 'multiple-choice',
            'label': 'Platforms',
            'options': ['android', 'ios', 'web'],
          },
        },
      });

      expect(group.variables, hasLength(2));
      expect(
        group.variables['project_type'],
        isA<FoundrySingleChoiceVariable<String>>()
            .having(
          (variable) => variable.label,
          'label',
          'Project type',
        )
            .having(
          (variable) => variable.options,
          'options',
          ['app', 'package'],
        ),
      );
      expect(
        group.variables['platforms'],
        isA<FoundryMultipleChoiceVariable<String>>()
            .having(
          (variable) => variable.label,
          'label',
          'Platforms',
        )
            .having(
          (variable) => variable.options,
          'options',
          ['android', 'ios', 'web'],
        ),
      );
    });

    test('throws when choice variable options are missing', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'project_type': {
              'kind': 'single-choice',
              'label': 'Project type',
            },
          },
        }),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.single.message,
            'message',
            'SingleChoice variable "project_type" is missing string options.',
          ),
        ),
      );
    });

    test('throws when choice variable options are not strings', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'platforms': {
              'kind': 'multiple-choice',
              'label': 'Platforms',
              'options': ['android', 1],
            },
          },
        }),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.single.message,
            'message',
            'MultipleChoice variable "platforms" has a non-string option.',
          ),
        ),
      );
    });

    test('throws when variables node is missing', () {
      expect(
        () => deserializeMoldVariableGroup({}),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('throws when variable definition is invalid', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'project_name': 'not-a-map',
          },
        }),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('throws when string variable label is missing', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'project_name': {
              'kind': 'string',
            },
          },
        }),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('throws when boolean variable label is missing', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'enabled': {
              'kind': 'boolean',
            },
          },
        }),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.single.message,
            'message',
            'Boolean variable "enabled" is missing a label.',
          ),
        ),
      );
    });

    test('throws for unsupported variable kinds', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'project_name': {
              'kind': 'unknown',
              'label': 'Project name',
            },
          },
        }),
        throwsA(isA<MoldLoadException>()),
      );
    });
  });
}
