import 'package:foundry_cli/src/tui/cast_variable_form.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

FoundryVariableGroup _buildVariableGroup() => FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(
          label: 'Project name',
          description: 'Used across generated files.',
          placeholder: 'my_app',
          help: 'Lowercase, underscores only.',
          validators: [
            (value, context) => (value == null || value.isEmpty)
                ? 'project_name is required'
                : null,
          ],
        ),
        'locked_field': FoundryStringVariable(
          label: 'Locked field',
          enabledWhen: (context) => false,
          defaultValue: (context) => 'locked-value',
        ),
        'hidden_field': FoundryStringVariable(
          label: 'Hidden field',
          visibleWhen: (context) => false,
        ),
        // Declared last so it's the last *visible* field: Enter on it
        // attempts submission. `locked_field` is visible but read-only, so
        // it can't be the field that triggers submission on Enter.
        'author': FoundryStringVariable(
          label: 'Author',
          defaultValue: (context) => 'Jane Doe',
        ),
      },
      groupValidators: [
        (context) => context.optionalString('author') == 'Nope'
            ? 'author cannot be "Nope"'
            : null,
      ],
    );

void main() {
  group('CastVariableForm', () {
    test(
      'renders header, visible fields, and hides hidden fields',
      () => testNocterm('renders fields', (tester) async {
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () {},
          ),
        );

        final output = tester.terminalState.getText();
        expect(output, contains('FOUNDRY // demo_app'));
        expect(output, contains('A demo mold.'));
        expect(output, contains('project_name: Project name'));
        expect(output, contains('Used across generated files.'));
        expect(output, contains('Lowercase, underscores only.'));
        expect(output, contains('author: Author'));
        expect(output, contains('Jane Doe'));
        expect(output, contains('locked_field: Locked field'));
        expect(output, isNot(contains('hidden_field')));
        expect(output, isNot(contains('Hidden field')));
      }),
    );

    test(
      'typing into the focused field marks it dirty',
      () => testNocterm('typing marks dirty', (tester) async {
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () {},
          ),
        );

        await tester.enterText('widgets');
        await tester.pump();

        expect(tester.terminalState.getText(), contains('widgets'));
      }),
    );

    test(
      'Tab moves focus forward and wraps around',
      () => testNocterm('tab forward', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        // project_name -> locked_field -> author -> back to project_name.
        await tester.sendTab();
        await tester.sendTab();
        await tester.sendTab();
        await tester.enterText('x');
        await tester.pump();

        expect(tester.terminalState.getText(), contains('x'));
        expect(submitted, isNull);
      }),
    );

    test(
      'Shift+Tab moves focus backward and wraps around',
      () => testNocterm('tab backward', (tester) async {
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () {},
          ),
        );

        // project_name -> wraps back to author (the last visible field).
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.tab,
            modifiers: ModifierKeys(shift: true),
          ),
        );
        await tester.enterText('Z');
        await tester.pump();

        expect(tester.terminalState.getText(), contains('Jane DoeZ'));
      }),
    );

    test(
      'Enter on a non-last field moves focus to the next field',
      () => testNocterm('enter moves focus', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        await tester.enterText('my_app');
        await tester.sendEnter();
        await tester.pump();

        expect(submitted, isNull);
      }),
    );

    test(
      'Enter on the last field with invalid values shows errors and does '
      'not submit',
      () => testNocterm('enter with invalid values', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        // Leave project_name empty (invalid) and move to the last field.
        await tester.sendTab();
        await tester.sendTab();
        await tester.sendEnter();
        await tester.pump();

        expect(submitted, isNull);
        expect(
          tester.terminalState.getText(),
          contains('project_name is required'),
        );
      }),
    );

    test(
      'Enter on the last field with a failing group validator shows the '
      'group error and does not submit',
      () => testNocterm('enter with group error', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        await tester.enterText('my_app');
        await tester.sendTab(); // -> locked_field (read-only, skipped)
        await tester.sendTab(); // -> author (last visible field)
        // Replace the "Jane Doe" default with the invalid "Nope" value.
        for (var i = 0; i < 'Jane Doe'.length; i++) {
          await tester.sendBackspace();
        }
        await tester.enterText('Nope');
        await tester.sendEnter();
        await tester.pump();

        expect(submitted, isNull);
        expect(
          tester.terminalState.getText(),
          contains('author cannot be "Nope"'),
        );
      }),
    );

    test(
      'Enter on the last field with valid values submits the resolved '
      'values',
      () => testNocterm('enter with valid values', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        await tester.enterText('my_app');
        await tester.sendTab();
        await tester.sendTab();
        await tester.sendEnter();
        await tester.pump();

        expect(submitted, isNotNull);
        expect(submitted!['project_name'], 'my_app');
        expect(submitted!['author'], 'Jane Doe');
        expect(submitted!['locked_field'], 'locked-value');
        expect(submitted!.containsKey('hidden_field'), isFalse);
      }),
    );

    test(
      'Escape cancels the form',
      () => testNocterm('escape cancels', (tester) async {
        var cancelled = false;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () => cancelled = true,
          ),
        );

        await tester.sendEscape();
        await tester.pump();

        expect(cancelled, isTrue);
      }),
    );

    test(
      'handles an empty variable group',
      () => testNocterm('empty group', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: const FoundryVariableGroup(variables: {}),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        await tester.sendTab();
        await tester.pump();

        expect(
          tester.terminalState.getText(),
          contains('FOUNDRY // demo_app'),
        );
        expect(submitted, isNull);
      }),
    );

    test(
      'disposes controllers when the form is unmounted',
      () => testNocterm('dispose controllers', (tester) async {
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: _buildVariableGroup(),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () {},
          ),
        );
        await tester.pumpComponent(const SizedBox());
        await tester.pump();
      }),
    );

    test(
      'clamps focus and drops controllers when a field becomes hidden',
      () => testNocterm('hidden field cleanup', (tester) async {
        final variableGroup = FoundryVariableGroup(
          variables: {
            'name': const FoundryStringVariable(label: 'Name'),
            'extra': FoundryStringVariable(
              label: 'Extra',
              visibleWhen: (context) =>
                  context.optionalString('tail') != 'hide',
            ),
            'tail': const FoundryStringVariable(label: 'Tail'),
          },
        );

        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: variableGroup,
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            onSubmit: (_) {},
            onCancel: () {},
          ),
        );

        await tester.sendTab();
        await tester.sendTab();
        await tester.enterText('hide');
        await tester.pump();

        expect(tester.terminalState.getText(), isNot(contains('extra: Extra')));
      }),
    );
  });
}
