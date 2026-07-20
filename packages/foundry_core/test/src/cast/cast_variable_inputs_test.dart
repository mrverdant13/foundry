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

FoundryVariableGroup _publishGroup() {
  return const FoundryVariableGroup(
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
    },
  );
}

FoundryVariableGroup _tagsGroup() {
  return const FoundryVariableGroup(
    variables: {
      'tags': FoundryValuesVariable<String>(
        label: 'Tags',
        item: FoundryStringVariable(label: 'Tag'),
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
      expect(success.isSuccess, isTrue);
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

    test('coerces whole JSON doubles to ints and accepts null JSON values', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 'Ada',
          'enabled': null,
          'port': 3.0,
        },
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['enabled'], isNull);
      expect(success.rawValues['port'], 3);
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

    test('treats an empty or whitespace vars flag as omitted', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {'name': 'Ada'},
        varsFlag: '   ',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
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
      expect(failure.hasErrors, isTrue);
    });

    test('reports type errors for JSON values', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFileValues: const {
          'name': 42,
          'enabled': 'yes',
          'port': 3.14,
          'scale': true,
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['name'], contains('string'));
      expect(failure.parseErrors['enabled'], contains('boolean'));
      expect(failure.parseErrors['port'], contains('integer'));
      expect(failure.parseErrors['scale'], contains('number'));
    });

    test('reports parse errors for flag values', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'name=Ada,enabled=maybe,port=pi,scale=nope',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['enabled'], 'Enter yes/no or true/false');
      expect(failure.parseErrors['port'], 'Enter a valid integer');
      expect(failure.parseErrors['scale'], 'Enter a valid number');
    });

    test('treats blank scalar flag values as null', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'name=Ada,enabled=,port=,scale=',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['enabled'], isNull);
      expect(success.rawValues['port'], isNull);
      expect(success.rawValues['scale'], isNull);
      // Explicit nulls are dirty, so defaults are not reapplied.
      expect(success.resolvedValues['port'], isNull);
      expect(success.resolvedValues['scale'], isNull);
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

    test('parses empty choice flag values', () {
      final result = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFlag: 'kind=,platforms=',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['kind'], isNull);
      expect(success.rawValues['platforms'], isEmpty);
    });

    test('rejects invalid choice tokens from flags and files', () {
      final flagResult = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFlag: 'kind=cli,platforms=android,desktop',
      );
      expect(flagResult, isA<CastVariableInputsParseFailure>());
      final flagFailure = flagResult as CastVariableInputsParseFailure;
      expect(flagFailure.parseErrors['kind'], 'Value is not a valid option.');
      expect(
        flagFailure.parseErrors['platforms'],
        'Value is not a valid option.',
      );

      final fileResult = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFileValues: const {
          'kind': true,
          'platforms': 'android',
        },
      );
      expect(fileResult, isA<CastVariableInputsParseFailure>());
      final fileFailure = fileResult as CastVariableInputsParseFailure;
      expect(fileFailure.parseErrors['kind'], 'Value is not a valid option.');
      expect(fileFailure.parseErrors['platforms'], contains('list of options'));
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

    test('matches choice options via displayLabel and scalar token forms', () {
      final group = FoundryVariableGroup(
        variables: {
          'tier': FoundrySingleChoiceVariable<int>(
            label: 'Tier',
            options: const [1, 2],
            displayLabel: (value) => 'tier-$value',
          ),
          'ratio': FoundrySingleChoiceVariable<double>(
            label: 'Ratio',
            options: const [0.5, 1.5],
            displayLabel: (value) => 'r$value',
          ),
          'flag': FoundrySingleChoiceVariable<bool>(
            label: 'Flag',
            options: const [true, false],
            displayLabel: (value) => value ? 'on' : 'off',
          ),
          'modes': FoundryMultipleChoiceVariable<int>(
            label: 'Modes',
            options: const [1, 2, 3],
            displayLabel: (value) => 'm$value',
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFlag: 'tier=tier-2,ratio=1.5,flag=yes,modes=m1,3',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.rawValues['tier'], 2);
      expect(success.rawValues['ratio'], 1.5);
      expect(success.rawValues['flag'], isTrue);
      expect(success.resolvedValues['modes'], [1, 3]);
    });

    test('rejects invalid JSON multi-choice option elements', () {
      final result = parseCastVariableInputs(
        variableGroup: _choiceGroup(),
        varsFileValues: const {
          'platforms': ['android', 'desktop'],
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(
        failure.parseErrors['platforms'],
        'Value is not a valid option.',
      );
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
      final result = parseCastVariableInputs(
        variableGroup: _publishGroup(),
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

    test('rejects non-object JSON for object variables', () {
      final result = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFileValues: const {
          'publish': ['not', 'a', 'map'],
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['publish'], contains('object'));
    });

    test('reports nested field type errors for object variables', () {
      final result = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFileValues: const {
          'publish': {
            'host': 1,
            'port': 'bad',
          },
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['publish.host'], contains('string'));
      expect(failure.parseErrors['publish.port'], contains('integer'));
    });

    test('parses object values from a JSON flag string', () {
      final result = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFlag: 'publish={"host":"h","port":9}',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.resolvedValues['publish'], {'host': 'h', 'port': 9});
    });

    test('rejects blank, non-JSON, invalid, and non-object object flags', () {
      expect(
        parseCastVariableInputs(
          variableGroup: _publishGroup(),
          varsFlag: 'publish=',
        ),
        isA<CastVariableInputsParseSuccess>(),
      );

      final plain = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFlag: 'publish=localhost',
      ) as CastVariableInputsParseFailure;
      expect(plain.parseErrors['publish'], contains('--vars-file'));

      final invalid = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFlag: 'publish={not-json',
      ) as CastVariableInputsParseFailure;
      expect(invalid.parseErrors['publish'], 'Invalid JSON object.');

      final notObject = parseCastVariableInputs(
        variableGroup: _publishGroup(),
        varsFlag: 'publish=[1]',
      ) as CastVariableInputsParseFailure;
      expect(notObject.parseErrors['publish'], 'Expected a JSON object.');
    });

    test('propagates nested failures inside nested object maps', () {
      const group = FoundryVariableGroup(
        variables: {
          'outer': FoundryObjectVariable(
            label: 'Outer',
            group: FoundryVariableGroup(
              variables: {
                'inner': FoundryObjectVariable(
                  label: 'Inner',
                  group: FoundryVariableGroup(
                    variables: {
                      'host': FoundryStringVariable(label: 'Host'),
                    },
                  ),
                ),
              },
            ),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFileValues: const {
          'outer': {
            'inner': {
              'host': 'ok',
              'extra': true,
            },
          },
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.unknownKeys, ['outer.inner.extra']);
    });

    test('rejects non-list JSON for values variables', () {
      final result = parseCastVariableInputs(
        variableGroup: _tagsGroup(),
        varsFileValues: const {
          'tags': {'a': 1},
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['tags'], contains('list'));
    });

    test('reports per-element type errors for values lists', () {
      const group = FoundryVariableGroup(
        variables: {
          'ports': FoundryValuesVariable<int>(
            label: 'Ports',
            item: FoundryIntVariable(label: 'Port'),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFileValues: const {
          'ports': [1, 'bad', 3],
        },
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['ports[1]'], contains('integer'));
    });

    test('propagates nested failures for values of objects', () {
      const group = FoundryVariableGroup(
        variables: {
          'items': FoundryValuesVariable<Map<String, Object?>>(
            label: 'Items',
            item: FoundryObjectVariable(
              label: 'Item',
              group: FoundryVariableGroup(
                variables: {
                  'host': FoundryStringVariable(label: 'Host'),
                },
              ),
            ),
          ),
        },
      );

      final fileResult = parseCastVariableInputs(
        variableGroup: group,
        varsFileValues: const {
          'items': [
            {'host': 'ok', 'extra': true},
          ],
        },
      );
      expect(fileResult, isA<CastVariableInputsParseFailure>());
      expect(
        (fileResult as CastVariableInputsParseFailure).unknownKeys,
        ['items[0].extra'],
      );

      final flagResult = parseCastVariableInputs(
        variableGroup: group,
        varsFlag: 'items={"extra":true}',
      );
      expect(flagResult, isA<CastVariableInputsParseFailure>());
      expect(
        (flagResult as CastVariableInputsParseFailure).unknownKeys,
        ['items[0].extra'],
      );
    });

    test('parses values lists from JSON array flags and empty lists', () {
      final empty = parseCastVariableInputs(
        variableGroup: _tagsGroup(),
        varsFlag: 'tags=',
      );
      expect(empty, isA<CastVariableInputsParseSuccess>());
      expect(
        (empty as CastVariableInputsParseSuccess).resolvedValues['tags'],
        isEmpty,
      );

      final jsonFlag = parseCastVariableInputs(
        variableGroup: _tagsGroup(),
        varsFlag: 'tags=["a","b"]',
      );
      expect(jsonFlag, isA<CastVariableInputsParseSuccess>());
      expect(
        (jsonFlag as CastVariableInputsParseSuccess).resolvedValues['tags'],
        ['a', 'b'],
      );

      final invalidJson = parseCastVariableInputs(
        variableGroup: _tagsGroup(),
        varsFlag: 'tags=[not-json',
      ) as CastVariableInputsParseFailure;
      expect(invalidJson.parseErrors['tags'], 'Invalid JSON array.');
    });

    test('reports flag parse errors for values-list scalar tokens', () {
      const group = FoundryVariableGroup(
        variables: {
          'ports': FoundryValuesVariable<int>(
            label: 'Ports',
            item: FoundryIntVariable(label: 'Port'),
          ),
        },
      );

      final result = parseCastVariableInputs(
        variableGroup: group,
        varsFlag: 'ports=1,bad,3',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.parseErrors['ports[1]'], 'Enter a valid integer');
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
      expect(failure.hasErrors, isTrue);
    });

    test('rejects a malformed vars flag string', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'not-a-pair',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.varsFlagError, contains('key=value'));
      expect(failure.hasErrors, isTrue);
    });

    test('rejects a vars flag with leading junk before the first pair', () {
      final result = parseCastVariableInputs(
        variableGroup: _scalarGroup(),
        varsFlag: 'junk,name=Ada',
      );

      expect(result, isA<CastVariableInputsParseFailure>());
      final failure = result as CastVariableInputsParseFailure;
      expect(failure.varsFlagError, contains('key=value'));
    });

    test('parses comma-separated values-list scalars from flags', () {
      final result = parseCastVariableInputs(
        variableGroup: _tagsGroup(),
        varsFlag: 'tags=one,two,three',
      );

      expect(result, isA<CastVariableInputsParseSuccess>());
      final success = result as CastVariableInputsParseSuccess;
      expect(success.resolvedValues['tags'], ['one', 'two', 'three']);
    });
  });

  group('CastVariableInputsParseFailure', () {
    test('toString includes flag, unknown, parse, and validation errors', () {
      const failure = CastVariableInputsParseFailure(
        varsFlagError: 'bad flag',
        unknownKeys: ['extra'],
        parseErrors: {'port': 'Enter a valid integer'},
        validation: FoundryVariableGroupValidation(
          fieldErrors: {
            'name': ['Required.'],
          },
          groupErrors: ['Group mismatch.'],
        ),
      );

      final text = failure.toString();
      expect(text, contains('bad flag'));
      expect(text, contains('Unknown variable "extra".'));
      expect(text, contains('port: Enter a valid integer'));
      expect(text, contains('name: Required.'));
      expect(text, contains('Group mismatch.'));
      expect(failure.hasErrors, isTrue);
      expect(failure.isSuccess, isFalse);
    });

    test('hasErrors is false for an empty failure shell', () {
      const failure = CastVariableInputsParseFailure();
      expect(failure.hasErrors, isFalse);
      expect(failure.toString(), 'Cast variable inputs failed:');
    });

    test('hasErrors is false when validation is present but valid', () {
      const failure = CastVariableInputsParseFailure(
        validation: FoundryVariableGroupValidation(
          fieldErrors: {},
          groupErrors: [],
        ),
      );
      expect(failure.hasErrors, isFalse);
      expect(failure.toString(), 'Cast variable inputs failed:');
    });
  });
}
