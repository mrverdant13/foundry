import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_variables_payload.dart';
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

    test('throws for unsupported variable kinds', () {
      expect(
        () => deserializeMoldVariableGroup({
          'variables': {
            'project_name': {
              'kind': 'boolean',
              'label': 'Enabled',
            },
          },
        }),
        throwsA(isA<MoldLoadException>()),
      );
    });
  });
}
