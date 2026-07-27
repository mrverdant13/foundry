import 'dart:io';

import 'package:foundry_cli/src/cast_session.dart';
import 'package:foundry_cli/src/cast_session_describe.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('describeMoldVariableGroup', () {
    test('reports copyable metadata and live choice labels', () {
      final descriptions = describeMoldVariableGroup(
        FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(
              label: 'Project name',
              description: 'UNIQUE_DESC_PROJECT_NAME',
              help: 'UNIQUE_HELP_PROJECT_NAME',
              placeholder: 'UNIQUE_PLACEHOLDER',
            ),
            'project_type': FoundrySingleChoiceVariable<String>(
              label: 'Project type',
              options: const {'app', 'package'},
              displayLabel: (value) => 'LABEL_$value',
            ),
            'tags': FoundryMultipleChoiceVariable<String>(
              label: 'Tags',
              options: const {'a', 'b'},
              displayLabel: (value) => 'TAG_$value',
            ),
            'count': FoundryIntVariable(label: 'Count'),
            'ratio': FoundryDoubleVariable(label: 'Ratio'),
            'enabled': FoundryBooleanVariable(label: 'Enabled'),
          },
        ),
      );

      expect(descriptions, hasLength(6));

      final projectName = descriptions.singleWhere(
        (entry) => entry.key == 'project_name',
      );
      expect(projectName.kind, 'string');
      expect(projectName.label, 'Project name');
      expect(projectName.description, 'UNIQUE_DESC_PROJECT_NAME');
      expect(projectName.help, 'UNIQUE_HELP_PROJECT_NAME');
      expect(projectName.placeholder, 'UNIQUE_PLACEHOLDER');

      final projectType = descriptions.singleWhere(
        (entry) => entry.key == 'project_type',
      );
      expect(projectType.kind, 'single-choice');
      expect(
        projectType.options.map((option) => option.label),
        ['LABEL_app', 'LABEL_package'],
      );
      expect(
        projectType.options.map((option) => option.value),
        ['app', 'package'],
      );

      final tags = descriptions.singleWhere((entry) => entry.key == 'tags');
      expect(tags.kind, 'multiple-choice');
      expect(tags.options.map((option) => option.label), ['TAG_a', 'TAG_b']);

      expect(
        descriptions.singleWhere((entry) => entry.key == 'count').kind,
        'int',
      );
      expect(
        descriptions.singleWhere((entry) => entry.key == 'ratio').kind,
        'double',
      );
      expect(
        descriptions.singleWhere((entry) => entry.key == 'enabled').kind,
        'boolean',
      );
    });

    test('describes nested object fields and values item schemas', () {
      final descriptions = describeMoldVariableGroup(
        FoundryVariableGroup(
          variables: {
            'author': FoundryObjectVariable(
              label: 'Author',
              group: FoundryVariableGroup(
                variables: {
                  'name': FoundryStringVariable(
                    label: 'Author name',
                    help: 'NESTED_HELP',
                  ),
                },
              ),
            ),
            'items': FoundryValuesVariable<String>(
              label: 'Items',
              item: FoundryStringVariable(
                label: 'Item',
                placeholder: 'ITEM_PLACEHOLDER',
              ),
            ),
          },
        ),
      );

      final author = descriptions.singleWhere((entry) => entry.key == 'author');
      expect(author.kind, 'object');
      expect(author.fields, hasLength(1));
      expect(author.fields.single.key, 'name');
      expect(author.fields.single.help, 'NESTED_HELP');

      final items = descriptions.singleWhere((entry) => entry.key == 'items');
      expect(items.kind, 'values');
      expect(items.item, isNotNull);
      expect(items.item!.placeholder, 'ITEM_PLACEHOLDER');
    });

    test('round-trips through JSON maps', () {
      final original = describeMoldVariableGroup(
        FoundryVariableGroup(
          variables: {
            'project_type': FoundrySingleChoiceVariable<String>(
              label: 'Project type',
              description: 'DESC',
              options: const {'app'},
              displayLabel: (value) => 'LABEL_$value',
            ),
          },
        ),
      ).single;

      final decoded = MoldVariableDescription.fromJson(original.toJson());
      expect(decoded.key, 'project_type');
      expect(decoded.kind, 'single-choice');
      expect(decoded.description, 'DESC');
      expect(decoded.options.single.label, 'LABEL_app');
      expect(decoded.options.single.value, 'app');
    });
  });

  group('CastSession.describeVariables', () {
    test('delegates to the live mold variable group', () {
      final moldDirectory = Directory.systemTemp.createTempSync(
        'foundry_describe_session_',
      );
      addTearDown(() {
        if (moldDirectory.existsSync()) {
          moldDirectory.deleteSync(recursive: true);
        }
      });

      final session = CastSession(
        mold: Mold(
          directory: moldDirectory,
          pubspec: const MoldPubspec(
            name: 'describe_demo',
            description: 'Describe session demo',
            version: '0.0.1',
          ),
          variableGroup: FoundryVariableGroup(
            variables: {
              'name': FoundryStringVariable(
                label: 'Name',
                help: 'LIVE_HELP',
              ),
            },
          ),
        ),
        outputPath: moldDirectory.path,
      );

      final descriptions = session.describeVariables();
      expect(descriptions, hasLength(1));
      expect(descriptions.single.help, 'LIVE_HELP');
    });
  });
}
