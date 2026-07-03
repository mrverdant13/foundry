import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('CastVariablesInvalidException', () {
    test('implements Exception', () {
      const validation = FoundryVariableGroupValidation(
        fieldErrors: {},
        groupErrors: [],
      );

      expect(
        const CastVariablesInvalidException(validation),
        isA<Exception>(),
      );
    });

    test('toString lists field and group errors', () {
      const validation = FoundryVariableGroupValidation(
        fieldErrors: {
          'project_name': ['must not be empty', 'must be lowercase'],
        },
        groupErrors: ['project_type is required'],
      );

      final message =
          const CastVariablesInvalidException(validation).toString();

      expect(message, contains('project_name: must not be empty'));
      expect(message, contains('project_name: must be lowercase'));
      expect(message, contains('project_type is required'));
    });

    test('toString omits sections with no errors', () {
      const validation = FoundryVariableGroupValidation(
        fieldErrors: {},
        groupErrors: ['project_type is required'],
      );

      final message =
          const CastVariablesInvalidException(validation).toString();

      expect(
        message,
        'Cast variables failed validation:\n  project_type is required',
      );
    });
  });
}
