import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

FoundryVariableGroup _scalarGroup() {
  return FoundryVariableGroup(
    variables: {
      'name': FoundryStringVariable(
        label: 'Name',
        validators: [
          (value, _) => (value == null || value.isEmpty) ? 'Required.' : null,
        ],
      ),
      'enabled': const FoundryBooleanVariable(label: 'Enabled'),
      'port': FoundryIntVariable(
        label: 'Port',
        defaultValue: (_) => 8080,
      ),
      'scale': FoundryDoubleVariable(
        label: 'Scale',
        defaultValue: (_) => 1.0,
      ),
    },
  );
}

FoundryVariableGroup _choiceGroup() {
  return FoundryVariableGroup(
    variables: {
      'kind': FoundrySingleChoiceVariable<String>(
        label: 'Kind',
        options: const ['app', 'package'],
        displayLabel: (value) => value,
      ),
      'platforms': FoundryMultipleChoiceVariable<String>(
        label: 'Platforms',
        options: const ['android', 'ios', 'web'],
        displayLabel: (value) => value,
      ),
    },
  );
}

void main() {
  group('parseCastVariableInputs', () {
    test('parses flags-only scalar inputs', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'name=Ada,enabled=true,port=443,scale=1.5',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues, {
        'name': 'Ada',
        'enabled': true,
        'port': 443,
        'scale': 1.5,
      });
      expect(success.resolvedValues['name'], 'Ada');
      expect(success.resolvedValues['port'], 443);
    });

    test('parses file-only JSON inputs', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 'Ada',
          'enabled': false,
          'port': 9000,
          'scale': 2,
        },
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['name'], 'Ada');
      expect(success.rawValues['enabled'], isFalse);
      expect(success.rawValues['port'], 9000);
      expect(success.rawValues['scale'], 2.0);
    });

    test('merges file then flag overrides colliding keys', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 'FromFile',
          'enabled': false,
          'port': 1,
        },
        varsFlag: 'name=FromFlag,port=2',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['name'], 'FromFlag');
      expect(success.rawValues['enabled'], isFalse);
      expect(success.rawValues['port'], 2);
      expect(success.resolvedValues['scale'], 1.0);
    });

    test('fails on unknown keys', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 'Ada',
          'extra': true,
        },
        varsFlag: 'also=1',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.unknownKeys, ['also', 'extra']);
      expect(failure.parseErrors, isEmpty);
      expect(failure.isSuccess, isFalse);
    });

    test('reports type errors for JSON values', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 42,
          'enabled': 'yes',
          'port': 3.14,
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['name'], contains('string'));
      expect(failure.parseErrors['enabled'], contains('boolean'));
      expect(failure.parseErrors['port'], contains('integer'));
    });

    test('reports parse errors for flag values', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'name=Ada,enabled=maybe,port=pi',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['enabled'], 'Enter yes/no or true/false');
      expect(failure.parseErrors['port'], 'Enter a valid integer');
    });

    test('keeps comma-separated multi-choice tokens inside a flag value', () {
      final result = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFlag: 'kind=app,platforms=android,ios',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['kind'], 'app');
      expect(success.rawValues['platforms'], ['android', 'ios']);
      expect(success.resolvedValues['platforms'], ['android', 'ios']);
    });

    test('parses choice values from a vars file', () {
      final result = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFileValues: const {
          'kind': 'package',
          'platforms': ['web', 'android'],
        },
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.resolvedValues['kind'], 'package');
      // Declaration order, not selection order.
      expect(success.resolvedValues['platforms'], ['android', 'web']);
    });

    test('parses nested object and values list from a vars file', () {
      const group = FoundryVariableGroup(
        variables: {
          'publish': FoundryObjectVariable(
            label: 'Publish',
            group: FoundryVariableGroup(
              variables: {
                'host': FoundryStringVariable(label: 'Host'),
                'port': FoundryIntVariable(label: 'Port'),
              },
            ),
          ),
          'tags': FoundryValuesVariable<String>(
            label: 'Tags',
            item: FoundryStringVariable(label: 'Tag'),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFileValues: const {
          'publish': {
            'host': 'api.example.com',
            'port': 443,
          },
          'tags': ['a', 'b'],
        },
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.resolvedValues['publish'], {
        'host': 'api.example.com',
        'port': 443,
      });
      expect(success.resolvedValues['tags'], ['a', 'b']);
    });

    test('fails on unknown nested object keys', () {
      const group = FoundryVariableGroup(
        variables: {
          'publish': FoundryObjectVariable(
            label: 'Publish',
            group: FoundryVariableGroup(
              variables: {
                'host': FoundryStringVariable(label: 'Host'),
              },
            ),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFileValues: const {
          'publish': {
            'host': 'localhost',
            'extra': true,
          },
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.unknownKeys, ['publish.extra']);
    });

    test('returns validation failures after a successful parse', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'name=',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.validation, isNotNull);
      expect(failure.validation!.isValid, isFalse);
      expect(failure.validation!.fieldErrors['name'], ['Required.']);
    });

    test('rejects a malformed vars flag string', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'not-a-pair',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.varsFlagError, contains('key=value'));
    });

    test('parses comma-separated values-list scalars from flags', () {
      const group = FoundryVariableGroup(
        variables: {
          'tags': FoundryValuesVariable<String>(
            label: 'Tags',
            item: FoundryStringVariable(label: 'Tag'),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFlag: 'tags=one,two,three',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.resolvedValues['tags'], ['one', 'two', 'three']);
    });
  });
}
