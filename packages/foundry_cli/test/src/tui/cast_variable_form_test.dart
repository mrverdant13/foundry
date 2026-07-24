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

FoundryVariableGroup _buildScalarVariableGroup() => FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(
          label: 'Project name',
          validators: [
            (value, context) => (value == null || value.isEmpty)
                ? 'project_name is required'
                : null,
          ],
        ),
        'publish': FoundryBooleanVariable(
          label: 'Publish',
          description: 'Upload the package.',
          help: 'Space toggles this field.',
          defaultValue: (context) => false,
        ),
        'port': FoundryIntVariable(
          label: 'Port',
          placeholder: '8080',
          help: 'Listening port.',
          defaultValue: (context) => 8080,
        ),
        'ratio': FoundryDoubleVariable(
          label: 'Ratio',
          description: 'Scaling factor.',
          defaultValue: (context) => 1.5,
        ),
        'locked_flag': FoundryBooleanVariable(
          label: 'Locked flag',
          enabledWhen: (context) => false,
          defaultValue: (context) => true,
        ),
      },
    );

FoundryVariableGroup _buildUnsetBooleanVariableGroup() =>
    const FoundryVariableGroup(
      variables: {
        'flag': FoundryBooleanVariable(
          label: 'Flag',
          description: 'Optional flag without a default.',
        ),
      },
    );

FoundryVariableGroup _buildChoiceVariableGroup() => FoundryVariableGroup(
      variables: {
        'project_type': FoundrySingleChoiceVariable<String>(
          label: 'Project type',
          description: 'What to generate.',
          help: 'Arrow keys move the selection.',
          options: const ['app', 'package'],
          displayLabel: (value) => value.toUpperCase(),
          defaultValue: (_) => 'app',
        ),
        'platforms': FoundryMultipleChoiceVariable<String>(
          label: 'Platforms',
          description: 'Target platforms.',
          help: 'Space toggles each option.',
          options: const ['android', 'ios', 'web'],
          displayLabel: (value) => value,
          defaultValue: (_) => const ['android'],
        ),
        'locked_type': FoundrySingleChoiceVariable<String>(
          label: 'Locked type',
          options: const ['app', 'package'],
          displayLabel: (value) => value,
          enabledWhen: (_) => false,
          defaultValue: (_) => 'package',
        ),
        'locked_platforms': FoundryMultipleChoiceVariable<String>(
          label: 'Locked platforms',
          options: const ['android', 'ios'],
          displayLabel: (value) => value,
          enabledWhen: (_) => false,
          defaultValue: (_) => const ['ios'],
        ),
      },
    );

FoundryVariableGroup _buildEmptyChoiceVariableGroup({
  required bool emptyChoiceLast,
}) {
  final emptyChoice = FoundrySingleChoiceVariable<String>(
    label: 'Empty choice',
    options: const <String>[],
    displayLabel: (value) => value,
  );
  final companion = FoundryStringVariable(
    label: 'Companion',
    defaultValue: (_) => 'ok',
  );

  return FoundryVariableGroup(
    variables: emptyChoiceLast
        ? {
            'companion': companion,
            'empty_choice': emptyChoice,
          }
        : {
            'empty_choice': emptyChoice,
            'companion': companion,
          },
  );
}

FoundryVariableGroup _buildOptionalMultiChoiceVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'platforms': FoundryMultipleChoiceVariable<String>(
          label: 'Platforms',
          options: const ['android', 'ios'],
          displayLabel: (value) => value,
        ),
      },
    );

FoundryVariableGroup _buildHidableChoiceVariableGroup() => FoundryVariableGroup(
      variables: {
        'mode': const FoundryStringVariable(label: 'Mode'),
        'kind': FoundrySingleChoiceVariable<String>(
          label: 'Kind',
          options: const ['a', 'b'],
          displayLabel: (value) => value,
          defaultValue: (_) => 'a',
          visibleWhen: (context) => context.optionalString('mode') != 'hide',
        ),
        'done': FoundryStringVariable(
          label: 'Done',
          defaultValue: (_) => 'x',
        ),
      },
    );

FoundryVariableGroup _buildChoiceFieldGroup() => FoundryVariableGroup(
      variables: {
        'field': FoundrySingleChoiceVariable<String>(
          label: 'Field',
          options: const ['app', 'package'],
          displayLabel: (value) => value,
          defaultValue: (_) => 'package',
        ),
      },
    );

FoundryVariableGroup _buildTextFieldGroup({String defaultText = 'typed'}) =>
    FoundryVariableGroup(
      variables: {
        'field': FoundryStringVariable(
          label: 'Field',
          defaultValue: (_) => defaultText,
        ),
      },
    );

FoundryVariableGroup _buildDerivedChoiceVariableGroup() => FoundryVariableGroup(
      variables: {
        'mode': const FoundryStringVariable(label: 'Mode'),
        'kind': FoundrySingleChoiceVariable<String>(
          label: 'Kind',
          options: const ['a', 'b'],
          displayLabel: (value) => value,
          defaultValue: (context) =>
              context.optionalString('mode') == 'b' ? 'b' : 'a',
        ),
      },
    );

FoundryVariableGroup _buildObjectVariableGroup() => FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(
          label: 'Project name',
          defaultValue: (_) => 'demo',
        ),
        'publish': FoundryObjectVariable(
          label: 'Publish settings',
          description: 'Where to publish.',
          help: 'Nested host, port, and secure flag.',
          group: FoundryVariableGroup(
            variables: {
              'host': FoundryStringVariable(
                label: 'Host',
                defaultValue: (_) => 'localhost',
                validators: [
                  (value, _) => (value == null || value.isEmpty)
                      ? 'Host is required.'
                      : null,
                ],
              ),
              'port': FoundryIntVariable(
                label: 'Port',
                defaultValue: (_) => 8080,
                visibleWhen: (context) =>
                    context.optionalString('host') != 'hidden',
              ),
              'secure': FoundryBooleanVariable(
                label: 'Secure',
                defaultValue: (_) => true,
                enabledWhen: (context) =>
                    context.optionalString('host') != 'locked',
              ),
            },
          ),
        ),
      },
    );

FoundryVariableGroup _buildDisabledObjectVariableGroup() {
  return FoundryVariableGroup(
    variables: {
      'publish': FoundryObjectVariable(
        label: 'Publish settings',
        enabledWhen: (_) => false,
        group: FoundryVariableGroup(
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => 'localhost',
            ),
            'secure': FoundryBooleanVariable(
              label: 'Secure',
              defaultValue: (_) => true,
            ),
          },
        ),
      ),
    },
  );
}

FoundryVariableGroup _buildValidatedObjectVariableGroup() {
  return FoundryVariableGroup(
    variables: {
      'publish': FoundryObjectVariable(
        label: 'Publish settings',
        validators: [
          (value, _) {
            final host = value?['host'];
            if (host == 'blocked') {
              return 'Host is blocked.';
            }
            return null;
          },
        ],
        group: FoundryVariableGroup(
          groupValidators: [
            (context) {
              final host = context.optionalString('host');
              final port = context.optionalInt('port');
              if (host == 'localhost' && port == 80) {
                return 'Localhost cannot use port 80.';
              }
              return null;
            },
          ],
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => 'localhost',
              validators: [
                (value, _) => (value == null || value.isEmpty)
                    ? 'Host is required.'
                    : null,
              ],
            ),
            'port': FoundryIntVariable(
              label: 'Port',
              defaultValue: (_) => 8080,
            ),
          },
        ),
      ),
    },
  );
}

FoundryVariableGroup _buildObjectFieldGroup({
  String hostDefault = 'localhost',
}) {
  return FoundryVariableGroup(
    variables: {
      'field': FoundryObjectVariable(
        label: 'Field',
        group: FoundryVariableGroup(
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => hostDefault,
            ),
          },
        ),
      ),
    },
  );
}

FoundryVariableGroup _buildDerivedNestedObjectVariableGroup() {
  return FoundryVariableGroup(
    variables: {
      'publish': FoundryObjectVariable(
        label: 'Publish settings',
        group: FoundryVariableGroup(
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => 'localhost',
            ),
            'port': FoundryIntVariable(
              label: 'Port',
              defaultValue: (context) =>
                  context.optionalString('host') == 'api.example.com'
                      ? 443
                      : 8080,
            ),
          },
        ),
      ),
    },
  );
}

FoundryVariableGroup _buildValuesVariableGroup() => FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(
          label: 'Project name',
          defaultValue: (_) => 'demo',
        ),
        'dependents': const FoundryValuesVariable<String>(
          label: 'Dependents',
          description: 'Packages this mold depends on.',
          help: 'Add, remove, or reorder package names.',
          item: FoundryStringVariable(
            label: 'Package name',
            placeholder: 'package_name',
          ),
        ),
      },
    );

FoundryVariableGroup _buildDefaultedValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'dependents': FoundryValuesVariable<String>(
          label: 'Dependents',
          item: const FoundryStringVariable(label: 'Package name'),
          defaultValue: (_) => const ['alpha', 'beta'],
        ),
      },
    );

FoundryVariableGroup _buildDisabledValuesVariableGroup() =>
    const FoundryVariableGroup(
      variables: {
        'dependents': FoundryValuesVariable<String>(
          label: 'Dependents',
          enabledWhen: _alwaysFalse,
          item: FoundryStringVariable(label: 'Package name'),
        ),
      },
    );

FoundryVariableGroup _buildValidatedValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'dependents': FoundryValuesVariable<String>(
          label: 'Dependents',
          item: const FoundryStringVariable(label: 'Package name'),
          validators: [
            (value, _) => (value == null || value.isEmpty)
                ? 'Add at least one dependent.'
                : null,
          ],
        ),
      },
    );

FoundryVariableGroup _buildObjectItemValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'servers': FoundryValuesVariable<Map<String, Object?>>(
          label: 'Servers',
          item: FoundryObjectVariable(
            label: 'Server',
            group: FoundryVariableGroup(
              variables: {
                'host': FoundryStringVariable(
                  label: 'Host',
                  defaultValue: (_) => 'localhost',
                ),
                'port': FoundryIntVariable(
                  label: 'Port',
                  defaultValue: (_) => 8080,
                ),
                'nested': FoundryObjectVariable(
                  label: 'Nested',
                  group: FoundryVariableGroup(
                    variables: {
                      'region': FoundryStringVariable(
                        label: 'Region',
                        defaultValue: (_) => 'us',
                      ),
                    },
                  ),
                ),
                'tags': const FoundryValuesVariable<String>(
                  label: 'Tags',
                  item: FoundryStringVariable(label: 'Tag'),
                ),
                'role': FoundrySingleChoiceVariable<String>(
                  label: 'Role',
                  options: const ['web', 'api'],
                  displayLabel: (value) => value,
                  defaultValue: (_) => 'web',
                ),
              },
            ),
          ),
        ),
      },
    );

FoundryVariableGroup _buildChoiceItemValuesVariableGroup({
  bool emptyOptions = false,
}) =>
    FoundryVariableGroup(
      variables: {
        'platforms': FoundryValuesVariable<String>(
          label: 'Platforms',
          item: FoundrySingleChoiceVariable<String>(
            label: 'Platform',
            options: emptyOptions ? const [] : const ['ios', 'android'],
            displayLabel: (value) => value,
          ),
        ),
      },
    );

FoundryVariableGroup _buildMultiChoiceItemValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'platforms': FoundryValuesVariable<List<String>>(
          label: 'Platforms',
          item: FoundryMultipleChoiceVariable<String>(
            label: 'Platforms',
            options: const ['ios', 'android'],
            displayLabel: (value) => value,
          ),
        ),
      },
    );

FoundryVariableGroup _buildNestedValuesInObjectVariableGroup() =>
    const FoundryVariableGroup(
      variables: {
        'publish': FoundryObjectVariable(
          label: 'Publish',
          group: FoundryVariableGroup(
            variables: {
              'hosts': FoundryValuesVariable<String>(
                label: 'Hosts',
                item: FoundryStringVariable(label: 'Host'),
              ),
            },
          ),
        ),
      },
    );

FoundryVariableGroup _buildNestedValuesItemVariableGroup() =>
    const FoundryVariableGroup(
      variables: {
        'groups': FoundryValuesVariable<List<String>>(
          label: 'Groups',
          item: FoundryValuesVariable<String>(
            label: 'Names',
            item: FoundryStringVariable(label: 'Name'),
          ),
        ),
      },
    );

FoundryVariableGroup _buildScalarItemValuesVariableGroup() =>
    const FoundryVariableGroup(
      variables: {
        'flags': FoundryValuesVariable<bool>(
          label: 'Flags',
          item: FoundryBooleanVariable(label: 'Flag'),
        ),
        'ports': FoundryValuesVariable<int>(
          label: 'Ports',
          item: FoundryIntVariable(label: 'Port'),
        ),
        'ratios': FoundryValuesVariable<double>(
          label: 'Ratios',
          item: FoundryDoubleVariable(label: 'Ratio'),
        ),
      },
    );

FoundryVariableGroup _buildDefaultedChoiceValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'platforms': FoundryValuesVariable<String>(
          label: 'Platforms',
          item: FoundrySingleChoiceVariable<String>(
            label: 'Platform',
            options: const ['ios', 'android'],
            displayLabel: (value) => value,
          ),
          defaultValue: (_) => const ['ios', 'android'],
        ),
      },
    );

FoundryVariableGroup _buildDefaultedObjectItemValuesVariableGroup() =>
    FoundryVariableGroup(
      variables: {
        'servers': FoundryValuesVariable<Map<String, Object?>>(
          label: 'Servers',
          item: const FoundryObjectVariable(
            label: 'Server',
            group: FoundryVariableGroup(
              variables: {
                'host': FoundryStringVariable(label: 'Host'),
                'port': FoundryIntVariable(label: 'Port'),
              },
            ),
          ),
          defaultValue: (_) => const [
            {'host': 'a.example.com', 'port': 80},
            {'host': 'b.example.com', 'port': 443},
          ],
        ),
      },
    );

bool _alwaysFalse(SnapshotFoundryContext context) => false;

FoundryVariableGroup _buildClearableNestedObjectVariableGroup() {
  return FoundryVariableGroup(
    variables: {
      'publish': FoundryObjectVariable(
        label: 'Publish settings',
        group: FoundryVariableGroup(
          variables: {
            'host': FoundryStringVariable(
              label: 'Host',
              defaultValue: (_) => 'localhost',
            ),
            'port': FoundryIntVariable(
              label: 'Port',
              defaultValue: (_) => 8080,
            ),
          },
        ),
      ),
    },
  );
}

/// Host that can swap [CastVariableForm.variableGroup] while preserving form
/// state, so kind-transition behavior is testable.
class _CastVariableFormHost extends StatefulComponent {
  const _CastVariableFormHost({
    required this.initialVariableGroup,
    required this.onBindSwap,
    required this.onSubmit,
    required this.onCancel,
  });

  final FoundryVariableGroup initialVariableGroup;
  final void Function(void Function(FoundryVariableGroup group) swap)
      onBindSwap;
  final void Function(Map<String, Object?> values) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_CastVariableFormHost> createState() => _CastVariableFormHostState();
}

class _CastVariableFormHostState extends State<_CastVariableFormHost> {
  late FoundryVariableGroup _variableGroup;

  @override
  void initState() {
    super.initState();
    _variableGroup = component.initialVariableGroup;
    component.onBindSwap((group) {
      setState(() => _variableGroup = group);
    });
  }

  @override
  Component build(BuildContext context) {
    return CastVariableForm(
      variableGroup: _variableGroup,
      moldName: 'demo_app',
      moldDescription: 'A demo mold.',
      onSubmit: component.onSubmit,
      onCancel: component.onCancel,
    );
  }
}

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
      'uses seedValues for defaultValue and visibleWhen during gather',
      () => testNocterm('seedValues defaults', (tester) async {
        Map<String, Object?>? submitted;
        await tester.pumpComponent(
          CastVariableForm(
            variableGroup: FoundryVariableGroup(
              variables: {
                'package_name': FoundryStringVariable(
                  label: 'Package name',
                  visibleWhen: (context) =>
                      context.optionalString('seed') == 'from-prepare',
                  defaultValue: (context) =>
                      context.optionalString('seed') ?? 'fallback',
                ),
              },
            ),
            moldName: 'demo_app',
            moldDescription: 'A demo mold.',
            seedValues: const {'seed': 'from-prepare'},
            onSubmit: (values) => submitted = values,
            onCancel: () {},
          ),
        );

        expect(tester.terminalState.getText(), contains('from-prepare'));
        await tester.sendEnter();
        await tester.pump();
        expect(submitted, isNotNull);
        expect(submitted!['package_name'], 'from-prepare');
      }),
    );

    test(
      'uses seedValues for nested object defaultValue and visibleWhen',
      () => testNocterm(
        'nested seedValues defaults',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: FoundryVariableGroup(
                variables: {
                  'publish': FoundryObjectVariable(
                    label: 'Publish settings',
                    group: FoundryVariableGroup(
                      variables: {
                        'host': FoundryStringVariable(
                          label: 'Host',
                          visibleWhen: (context) =>
                              context.optionalString('seed') == 'from-prepare',
                          defaultValue: (context) =>
                              context.optionalString('seed') ?? 'fallback',
                        ),
                      },
                    ),
                  ),
                },
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              seedValues: const {'seed': 'from-prepare'},
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('host: Host'));
          expect(output, contains('from-prepare'));
          await tester.sendEnter();
          await tester.pump();
          expect(submitted, isNotNull);
          expect(submitted!['publish'], {'host': 'from-prepare'});
        },
      ),
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

    test(
      'renders boolean and numeric fields with metadata',
      () => testNocterm(
        'renders scalar fields',
        size: const Size(80, 40),
        (tester) async {
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (_) {},
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('publish: Publish'));
          expect(output, contains('Upload the package.'));
          expect(output, contains('Space toggles this field.'));
          expect(output, contains('[ ] no'));
          expect(output, contains('port: Port'));
          expect(output, contains('Listening port.'));
          expect(output, contains('8080'));
          expect(output, contains('ratio: Ratio'));
          expect(output, contains('Scaling factor.'));
          expect(output, contains('1.5'));
          expect(output, contains('locked_flag: Locked flag'));
          expect(output, contains('[x] yes (read-only)'));
          expect(output, contains('project_name: Project name'));
        },
      ),
    );

    test(
      'Enter on a non-last boolean field moves focus to the next field',
      () => testNocterm(
        'enter on boolean moves focus',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.enterText('my_app');
          await tester.sendTab(); // publish (boolean, not last)
          await tester.sendEnter();
          await tester.pump();

          // Focus should now be on port; typing replaces its default.
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('3000');
          await tester.pump();

          expect(submitted, isNull);
          expect(tester.terminalState.getText(), contains('3000'));
        },
      ),
    );

    test(
      'Space toggles an enabled boolean and submits typed scalar values',
      () => testNocterm(
        'toggle boolean and submit scalars',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.enterText('my_app');
          await tester.sendTab(); // publish
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          expect(tester.terminalState.getText(), contains('[x] yes'));

          await tester.sendTab(); // port
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('3000');
          await tester.sendTab(); // ratio
          for (var i = 0; i < '1.5'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('2.25');
          await tester.sendTab(); // locked_flag (last)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['project_name'], 'my_app');
          expect(submitted!['publish'], isTrue);
          expect(submitted!['port'], 3000);
          expect(submitted!['ratio'], 2.25);
          expect(submitted!['locked_flag'], isTrue);
        },
      ),
    );

    test(
      'Space does not toggle a disabled boolean field',
      () => testNocterm(
        'disabled boolean stays put',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.enterText('my_app');
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendTab(); // locked_flag
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            contains('[x] yes (read-only)'),
          );

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['locked_flag'], isTrue);
          expect(submitted!['publish'], isFalse);
        },
      ),
    );

    test(
      'renders an explicit unset label for a boolean without a default',
      () => testNocterm(
        'unset boolean label',
        (tester) async {
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildUnsetBooleanVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (_) {},
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('flag: Flag'));
          expect(output, contains('[-] unset'));
          expect(output, isNot(contains('[ ] no')));
        },
      ),
    );

    test(
      'submitting an untouched boolean without a default yields null',
      () => testNocterm(
        'unset boolean submits null',
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildUnsetBooleanVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('[-] unset'));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!.containsKey('flag'), isTrue);
          expect(submitted!['flag'], isNull);
        },
      ),
    );

    test(
      'invalid int input stays in-form with a parse error and does not '
      'submit',
      () => testNocterm(
        'invalid int stays in form',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.enterText('my_app');
          await tester.sendTab(); // publish
          await tester.sendTab(); // port
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('abc');
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            contains('Enter a valid integer'),
          );

          await tester.sendTab(); // ratio
          await tester.sendTab(); // locked_flag
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Enter a valid integer'),
          );
          expect(tester.terminalState.getText(), contains('abc'));
        },
      ),
    );

    test(
      'invalid double input stays in-form with a parse error and does not '
      'submit',
      () => testNocterm(
        'invalid double stays in form',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.enterText('my_app');
          await tester.sendTab(); // publish
          await tester.sendTab(); // port
          await tester.sendTab(); // ratio
          for (var i = 0; i < '1.5'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('pi');
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            contains('Enter a valid number'),
          );

          await tester.sendTab(); // locked_flag
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Enter a valid number'),
          );
          expect(tester.terminalState.getText(), contains('pi'));
        },
      ),
    );

    test(
      'renders single and multiple choice fields with displayLabel metadata',
      () => testNocterm(
        'renders choice fields',
        size: const Size(80, 40),
        (tester) async {
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (_) {},
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('project_type: Project type'));
          expect(output, contains('What to generate.'));
          expect(output, contains('Arrow keys move the selection.'));
          expect(output, contains('(•) APP'));
          expect(output, contains('( ) PACKAGE'));
          expect(output, contains('platforms: Platforms'));
          expect(output, contains('Target platforms.'));
          expect(output, contains('Space toggles each option.'));
          expect(output, contains('[x] android'));
          expect(output, contains('[ ] ios'));
          expect(output, contains('[ ] web'));
          expect(output, contains('locked_type: Locked type'));
          expect(output, contains('(•) package'));
          expect(output, contains('(read-only)'));
          expect(output, contains('locked_platforms: Locked platforms'));
          expect(output, contains('[x] ios'));
        },
      ),
    );

    test(
      'selects one and many options and submits resolved choice values',
      () => testNocterm(
        'select and submit choices',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          // project_type: move from app -> package
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) PACKAGE'));

          await tester.sendTab(); // platforms
          // Leave android checked; toggle ios and web on.
          await tester.sendKey(LogicalKey.arrowDown); // ios
          await tester.sendKey(LogicalKey.space);
          await tester.sendKey(LogicalKey.arrowDown); // web
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          final output = tester.terminalState.getText();
          expect(output, contains('[x] android'));
          expect(output, contains('[x] ios'));
          expect(output, contains('[x] web'));

          await tester.sendTab(); // locked_type
          await tester.sendTab(); // locked_platforms (last)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['project_type'], 'package');
          expect(submitted!['platforms'], ['android', 'ios', 'web']);
          expect(submitted!['locked_type'], 'package');
          expect(submitted!['locked_platforms'], ['ios']);
        },
      ),
    );

    test(
      'Space and arrows do not edit disabled choice fields',
      () => testNocterm(
        'disabled choices stay put',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // platforms
          await tester.sendTab(); // locked_type
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            contains('(•) package'),
          );
          expect(
            tester.terminalState.getText(),
            contains('(read-only)'),
          );

          await tester.sendTab(); // locked_platforms
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          expect(tester.terminalState.getText(), contains('[x] ios'));
          expect(tester.terminalState.getText(), contains('[ ] android'));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['locked_type'], 'package');
          expect(submitted!['locked_platforms'], ['ios']);
          expect(submitted!['project_type'], 'app');
          expect(submitted!['platforms'], ['android']);
        },
      ),
    );

    test(
      'Enter on a non-last choice field moves focus to the next field',
      () => testNocterm(
        'enter on choice moves focus',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendEnter(); // project_type -> platforms
          await tester.sendKey(LogicalKey.arrowDown); // ios
          await tester.sendKey(LogicalKey.space);
          await tester.pump();

          expect(submitted, isNull);
          expect(tester.terminalState.getText(), contains('[x] ios'));
        },
      ),
    );

    test(
      'arrow up wraps a single-choice selection and Space selects it',
      () => testNocterm(
        'arrow up and space on single choice',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          // Default is app (index 0); arrow up wraps to package.
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) PACKAGE'));

          await tester.sendKey(LogicalKey.arrowDown); // back to app
          await tester.sendKey(LogicalKey.space); // select app via Space
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) APP'));

          await tester.sendTab(); // platforms
          // Toggle the default android selection off.
          await tester.sendKey(LogicalKey.space);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('[ ] android'));

          await tester.sendTab(); // locked_type
          await tester.sendTab(); // locked_platforms
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['project_type'], 'app');
          expect(submitted!['platforms'], equals(<String>[]));
        },
      ),
    );

    test(
      'Enter on a non-last empty choice field moves focus',
      () => testNocterm(
        'enter on empty choice moves focus',
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildEmptyChoiceVariableGroup(
                emptyChoiceLast: false,
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(
            tester.terminalState.getText(),
            contains('empty_choice: Empty choice'),
          );

          await tester.sendKey(LogicalKey.space); // ignored for empty options
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);

          // Focus should now be on companion; typing replaces its default.
          for (var i = 0; i < 'ok'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('next');
          await tester.pump();
          expect(tester.terminalState.getText(), contains('next'));
        },
      ),
    );

    test(
      'Enter on a last empty choice field submits',
      () => testNocterm(
        'enter on empty choice submits',
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildEmptyChoiceVariableGroup(
                emptyChoiceLast: true,
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // empty_choice (last)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['companion'], 'ok');
          expect(submitted!.containsKey('empty_choice'), isTrue);
          expect(submitted!['empty_choice'], isNull);
        },
      ),
    );

    test(
      'renders an optional multi-choice with no selection',
      () => testNocterm(
        'optional multi choice unset',
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildOptionalMultiChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('[ ] android'));
          expect(output, contains('[ ] ios'));

          await tester.sendKey(LogicalKey.space);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('[x] android'));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['platforms'], ['android']);
        },
      ),
    );

    test(
      'drops choice state when a choice field becomes hidden',
      () => testNocterm(
        'hidden choice cleanup',
        size: const Size(80, 40),
        (tester) async {
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildHidableChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (_) {},
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('kind: Kind'));

          await tester.enterText('hide');
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            isNot(contains('kind: Kind')),
          );
          expect(tester.terminalState.getText(), contains('done: Done'));
        },
      ),
    );

    test(
      'choice-to-text kind change drops stale choice values',
      () => testNocterm(
        'choice to text kind change',
        (tester) async {
          Map<String, Object?>? submitted;
          late void Function(FoundryVariableGroup group) swapGroup;

          await tester.pumpComponent(
            _CastVariableFormHost(
              initialVariableGroup: _buildChoiceFieldGroup(),
              onBindSwap: (swap) => swapGroup = swap,
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('(•) package'));

          // Dirty the choice field so a stale raw value exists before the swap.
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) app'));

          swapGroup(_buildTextFieldGroup(defaultText: 'typed-default'));
          await tester.pump();

          final output = tester.terminalState.getText();
          expect(output, contains('typed-default'));
          expect(output, isNot(contains('(•)')));

          for (var i = 0; i < 'typed-default'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('hello');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['field'], 'hello');
        },
      ),
    );

    test(
      'text-to-choice kind change drops stale text controllers',
      () => testNocterm(
        'text to choice kind change',
        (tester) async {
          Map<String, Object?>? submitted;
          late void Function(FoundryVariableGroup group) swapGroup;

          await tester.pumpComponent(
            _CastVariableFormHost(
              initialVariableGroup: _buildTextFieldGroup(defaultText: 'stale'),
              onBindSwap: (swap) => swapGroup = swap,
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          for (var i = 0; i < 'stale'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('keep-me');
          await tester.pump();
          expect(tester.terminalState.getText(), contains('keep-me'));

          swapGroup(_buildChoiceFieldGroup());
          await tester.pump();

          final output = tester.terminalState.getText();
          expect(output, contains('(•) package'));
          expect(output, isNot(contains('keep-me')));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['field'], 'package');
        },
      ),
    );

    test(
      'resyncs a non-dirty single-choice cursor when the default changes',
      () => testNocterm(
        'cursor tracks derived default',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDerivedChoiceVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('(•) a'));

          await tester.enterText('b');
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) b'));

          await tester.sendTab(); // kind
          expect(tester.terminalState.getText(), contains('> (•) b'));

          // Space should keep the synced selection, not the old cursor option.
          await tester.sendKey(LogicalKey.space);
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['mode'], 'b');
          expect(submitted!['kind'], 'b');
        },
      ),
    );

    test(
      'gathers a nested object map from nested field widgets',
      () => testNocterm(
        'gather nested object map',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('publish: Publish settings'));
          expect(output, contains('host: Host'));
          expect(output, contains('port: Port'));
          expect(output, contains('secure: Secure'));

          await tester.sendTab(); // publish.host
          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('api.example.com');
          await tester.sendTab(); // publish.port
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('443');
          await tester.sendTab(); // publish.secure
          await tester.sendKey(LogicalKey.space); // true -> false
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['project_name'], 'demo');
          expect(submitted!['publish'], {
            'host': 'api.example.com',
            'port': 443,
            'secure': false,
          });
        },
      ),
    );

    test(
      'honors nested visibleWhen by hiding nested fields',
      () => testNocterm(
        'nested visibleWhen',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('port: Port'));

          await tester.sendTab(); // publish.host
          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('hidden');
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            isNot(contains('port: Port')),
          );
          expect(tester.terminalState.getText(), contains('secure: Secure'));

          await tester.sendTab(); // publish.secure
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'host': 'hidden',
            'secure': true,
          });
          expect(
            (submitted!['publish']! as Map).containsKey('port'),
            isFalse,
          );
        },
      ),
    );

    test(
      'honors nested enabledWhen with a read-only nested boolean',
      () => testNocterm(
        'nested enabledWhen',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // publish.host
          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('locked');
          await tester.pump();

          expect(
            tester.terminalState.getText(),
            contains('[x] yes (read-only)'),
          );

          await tester.sendTab(); // publish.port
          await tester.sendTab(); // publish.secure
          await tester.sendKey(LogicalKey.space); // ignored
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'host': 'locked',
            'port': 8080,
            'secure': true,
          });
        },
      ),
    );

    test(
      'marks nested fields read-only when the parent object is disabled',
      () => testNocterm(
        'disabled parent object',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDisabledObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('publish: Publish settings'));
          expect(output, contains('(read-only)'));
          expect(output, contains('[x] yes (read-only)'));

          await tester.sendKey(LogicalKey.space); // ignored on nested boolean
          await tester.sendTab(); // host -> secure
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'host': 'localhost',
            'secure': true,
          });
        },
      ),
    );

    test(
      'shows nested field errors when object submit is invalid',
      () => testNocterm(
        'nested field validation errors',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValidatedObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.sendTab(); // port
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Host is required.'),
          );
        },
      ),
    );

    test(
      'shows nested group errors on the object section',
      () => testNocterm(
        'nested group validation errors',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValidatedObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // port
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('80');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Localhost cannot use port 80.'),
          );
        },
      ),
    );

    test(
      'shows object-level validator errors on the object section',
      () => testNocterm(
        'object validator errors',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValidatedObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('blocked');
          await tester.sendTab(); // port
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Host is blocked.'),
          );
        },
      ),
    );

    test(
      'text-to-object kind change drops stale text controllers',
      () => testNocterm(
        'text to object kind change',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          late void Function(FoundryVariableGroup group) swapGroup;

          await tester.pumpComponent(
            _CastVariableFormHost(
              initialVariableGroup: _buildTextFieldGroup(defaultText: 'stale'),
              onBindSwap: (swap) => swapGroup = swap,
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          for (var i = 0; i < 'stale'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('keep-me');
          await tester.pump();
          expect(tester.terminalState.getText(), contains('keep-me'));

          swapGroup(_buildObjectFieldGroup(hostDefault: 'nested-host'));
          await tester.pump();

          final output = tester.terminalState.getText();
          expect(output, contains('field: Field'));
          expect(output, contains('host: Host'));
          expect(output, contains('nested-host'));
          expect(output, isNot(contains('keep-me')));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['field'], {'host': 'nested-host'});
        },
      ),
    );

    test(
      'choice-to-object kind change drops stale choice values',
      () => testNocterm(
        'choice to object kind change',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          late void Function(FoundryVariableGroup group) swapGroup;

          await tester.pumpComponent(
            _CastVariableFormHost(
              initialVariableGroup: _buildChoiceFieldGroup(),
              onBindSwap: (swap) => swapGroup = swap,
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(•) app'));

          swapGroup(_buildObjectFieldGroup(hostDefault: 'from-object'));
          await tester.pump();

          final output = tester.terminalState.getText();
          expect(output, contains('field: Field'));
          expect(output, contains('from-object'));
          expect(output, isNot(contains('(•)')));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['field'], {'host': 'from-object'});
        },
      ),
    );

    test(
      'recomputes a nested default when a sibling nested field changes',
      () => testNocterm(
        'nested derived default',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDerivedNestedObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('8080'));

          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('api.example.com');
          await tester.pump();

          expect(tester.terminalState.getText(), contains('443'));

          await tester.sendTab(); // port
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'host': 'api.example.com',
            'port': 443,
          });
        },
      ),
    );

    test(
      'submits null when a nested int field is cleared',
      () => testNocterm(
        'nested cleared int submits null',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildClearableNestedObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // port
          for (var i = 0; i < '8080'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.pump();
          expect(tester.terminalState.getText(), isNot(contains('8080')));

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'host': 'localhost',
            'port': null,
          });
        },
      ),
    );

    test(
      'submits an empty values list when no items are added',
      () => testNocterm(
        'empty values list submit',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          final output = tester.terminalState.getText();
          expect(output, contains('dependents: Dependents'));
          expect(output, contains('(empty list)'));

          await tester.sendTab(); // project_name -> dependents chrome
          await tester.sendEnter(); // last focus target
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['project_name'], 'demo');
          expect(submitted!['dependents'], equals(<String>[]));
        },
      ),
    );

    test(
      'adds edits and submits values list items',
      () => testNocterm(
        'add and submit values list',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // dependents chrome
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();

          expect(tester.terminalState.getText(), contains('2 items'));

          await tester.sendTab(); // item 0
          await tester.enterText('pkg_a');
          await tester.sendTab(); // item 1
          await tester.enterText('pkg_b');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['pkg_a', 'pkg_b']);
        },
      ),
    );

    test(
      'removes a values list item before submit',
      () => testNocterm(
        'remove values list item',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('2 items'));

          // Dirty item [1] first so remove copies dirty state onto [0].
          await tester.sendTab(); // item 0
          await tester.sendTab(); // item 1
          await tester.enterText('_x');
          await tester.sendTab(); // chrome
          // Cursor still on [0]; delete alpha and shift beta_x down.
          await tester.sendKey(LogicalKey.keyD);
          await tester.pump();

          expect(tester.terminalState.getText(), contains('1 item'));
          expect(tester.terminalState.getText(), contains('beta_x'));

          await tester.sendTab(); // remaining item
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['beta_x']);
        },
      ),
    );

    test(
      'reorders values list items with Shift+arrow keys',
      () => testNocterm(
        'reorder values list with Shift+arrow',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('alpha'));
          expect(tester.terminalState.getText(), contains('beta'));

          // Cursor on [0] (alpha); move it down past beta.
          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.arrowDown,
              modifiers: ModifierKeys(shift: true),
            ),
          );
          await tester.pump();

          // Visible TextField text must swap (not only the submitted model).
          final reordered = tester.terminalState.getText();
          expect(
            reordered.indexOf('beta'),
            lessThan(reordered.indexOf('alpha')),
          );

          await tester.sendTab(); // item 0 (now beta)
          await tester.sendTab(); // item 1 (now alpha)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['beta', 'alpha']);
        },
      ),
    );

    test(
      'reorders values list items with k/j keys',
      () => testNocterm(
        'reorder values list with k/j',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          // Cursor on [0] (alpha); j moves it down past beta.
          await tester.sendKey(LogicalKey.keyJ);
          await tester.pump();

          final reordered = tester.terminalState.getText();
          expect(
            reordered.indexOf('beta'),
            lessThan(reordered.indexOf('alpha')),
          );

          await tester.sendTab(); // item 0 (now beta)
          await tester.sendTab(); // item 1 (now alpha)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['beta', 'alpha']);
        },
      ),
    );

    test(
      'reorders values list items upward and via Ctrl+arrow',
      () => testNocterm(
        'reorder values list upward',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.arrowDown); // cursor [1]
          await tester.sendKey(LogicalKey.keyK); // move beta up
          await tester.pump();

          var output = tester.terminalState.getText();
          expect(output.indexOf('beta'), lessThan(output.indexOf('alpha')));

          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.arrowDown,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );
          await tester.pump();

          output = tester.terminalState.getText();
          expect(output.indexOf('alpha'), lessThan(output.indexOf('beta')));

          await tester.sendKey(LogicalKey.arrowUp);
          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.arrowUp,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['alpha', 'beta']);
        },
      ),
    );

    test(
      'moves values list cursor with arrow keys on empty and populated lists',
      () => testNocterm(
        'values list cursor arrows',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // list chrome
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();

          expect(tester.terminalState.getText(), contains('cursor on [1]'));
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('cursor on [0]'));
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('cursor on [1]'));

          await tester.sendKey(LogicalKey.keyD);
          await tester.sendKey(LogicalKey.delete);
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], equals(<String>[]));
        },
      ),
    );

    test(
      'Enter on values chrome moves focus into the first item',
      () => testNocterm(
        'enter on values chrome moves focus',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendEnter(); // chrome -> item 0
          for (var i = 0; i < 'alpha'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('gamma');
          await tester.sendEnter(); // item 0 -> item 1
          await tester.sendEnter(); // submit
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['gamma', 'beta']);
        },
      ),
    );

    test(
      'disabled values list shows read-only chrome',
      () => testNocterm(
        'disabled values list',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDisabledValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('(read-only)'));
          await tester.sendKey(LogicalKey.keyA); // ignored
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], equals(<String>[]));
        },
      ),
    );

    test(
      'shows list-level validator errors on the values section',
      () => testNocterm(
        'values list validator errors',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildValidatedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Add at least one dependent.'),
          );
        },
      ),
    );

    test(
      'gathers object items including nested object values and choice fields',
      () => testNocterm(
        'values object items',
        size: const Size(100, 60),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildObjectItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('[0]'));

          await tester.sendTab(); // host
          for (var i = 0; i < 'localhost'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('api.example.com');
          await tester.sendTab(); // port
          await tester.sendTab(); // nested.region
          for (var i = 0; i < 'us'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('eu');
          await tester.sendTab(); // tags chrome
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab(); // tag item
          await tester.enterText('edge');
          await tester.sendTab(); // role
          await tester.sendKey(LogicalKey.arrowDown); // api
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['servers'], [
            {
              'host': 'api.example.com',
              'port': 8080,
              'nested': {'region': 'eu'},
              'tags': ['edge'],
              'role': 'api',
            },
          ]);
        },
      ),
    );

    test(
      'gathers single-choice values items',
      () => testNocterm(
        'values choice items',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();
          await tester.sendTab(); // item 0
          await tester.sendKey(LogicalKey.arrowDown); // android
          await tester.sendTab(); // item 1 (ios)
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['platforms'], ['android', 'ios']);
        },
      ),
    );

    test(
      'ignores add for empty-option single-choice values items',
      () => testNocterm(
        'values empty choice items',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildChoiceItemValuesVariableGroup(
                emptyOptions: true,
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('(empty list)'));
          await tester.sendEnter();
          await tester.pump();
          expect(submitted, isNotNull);
          expect(submitted!['platforms'], equals(<String>[]));
        },
      ),
    );

    test(
      'gathers multiple-choice values items',
      () => testNocterm(
        'values multi choice items',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildMultiChoiceItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab();
          await tester.sendKey(LogicalKey.space); // ios
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['platforms'], [
            ['ios'],
          ]);
        },
      ),
    );

    test(
      'gathers values nested inside an object variable',
      () => testNocterm(
        'values nested in object',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildNestedValuesInObjectVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab();
          await tester.enterText('cdn.example.com');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['publish'], {
            'hosts': ['cdn.example.com'],
          });
        },
      ),
    );

    test(
      'gathers nested values-of-values items',
      () => testNocterm(
        'values of values',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildNestedValuesItemVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA); // outer item
          await tester.sendTab(); // nested chrome
          await tester.sendKey(LogicalKey.keyA); // nested item
          await tester.sendTab();
          await tester.enterText('one');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['groups'], [
            ['one'],
          ]);
        },
      ),
    );

    test(
      'adds boolean int and double values items',
      () => testNocterm(
        'scalar values items',
        size: const Size(80, 50),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA); // flags
          await tester.sendTab(); // flag item
          await tester.sendKey(LogicalKey.space); // true
          await tester.sendTab(); // ports chrome
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab(); // port item
          for (var i = 0; i < '0'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('443');
          await tester.sendTab(); // ratios chrome
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab(); // ratio item
          for (var i = 0; i < '0.0'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('1.5');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['flags'], [true]);
          expect(submitted!['ports'], [443]);
          expect(submitted!['ratios'], [1.5]);
        },
      ),
    );

    test(
      'invalid numeric values item stays in-form with a parse error',
      () => testNocterm(
        'invalid values int item',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildScalarItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // ports chrome
          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab();
          for (var i = 0; i < '0'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('nope');
          await tester.sendTab(); // ratios
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Enter a valid integer'),
          );
        },
      ),
    );

    test(
      'cleared numeric values item uses a typed placeholder on submit',
      () => testNocterm(
        'cleared values int item',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: const FoundryVariableGroup(
                variables: {
                  'ports': FoundryValuesVariable<int>(
                    label: 'Ports',
                    item: FoundryIntVariable(label: 'Port'),
                  ),
                },
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab();
          await tester.sendBackspace(); // clear seeded 0
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['ports'], [0]);
        },
      ),
    );

    test(
      'editing a defaulted values item marks descendant dirty keys',
      () => testNocterm(
        'values descendant dirty',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // item 0
          await tester.enterText('_x');
          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['dependents'], ['alpha_x', 'beta']);
        },
      ),
    );

    test(
      'reorders defaulted choice values items with asymmetric dirty state',
      () => testNocterm(
        'reorder dirty choice values',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedChoiceValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // item 0
          await tester.sendKey(LogicalKey.arrowDown); // android (dirty)
          await tester.sendTab(); // item 1
          await tester.sendTab(); // wrap to chrome
          await tester.sendKey(LogicalKey.keyJ);
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['platforms'], ['android', 'android']);
        },
      ),
    );

    test(
      'removes an object values item and keeps the remaining item',
      () => testNocterm(
        'remove object values item',
        size: const Size(100, 60),
        (tester) async {
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildObjectItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (_) {},
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendKey(LogicalKey.keyA);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('2 items'));
          expect(tester.terminalState.getText(), contains('[0]'));
          expect(tester.terminalState.getText(), contains('[1]'));

          await tester.sendKey(LogicalKey.keyD); // remove cursor item [0]
          await tester.pump();
          expect(tester.terminalState.getText(), contains('1 item'));
          expect(tester.terminalState.getText(), contains('[0]'));
          expect(tester.terminalState.getText(), isNot(contains('[1]')));
          expect(tester.terminalState.getText(), contains('localhost'));
        },
      ),
    );

    test(
      'invalid double values item stays in-form with a parse error',
      () => testNocterm(
        'invalid values double item',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: const FoundryVariableGroup(
                variables: {
                  'ratios': FoundryValuesVariable<double>(
                    label: 'Ratios',
                    item: FoundryDoubleVariable(label: 'Ratio'),
                  ),
                },
              ),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendKey(LogicalKey.keyA);
          await tester.sendTab();
          for (var i = 0; i < '0.0'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('nope');
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Enter a valid number'),
          );
        },
      ),
    );

    test(
      'renders defaulted object values items from resolved maps',
      () => testNocterm(
        'defaulted object values items',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedObjectItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('a.example.com'));
          expect(tester.terminalState.getText(), contains('b.example.com'));

          await tester.sendTab();
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['servers'], [
            {'host': 'a.example.com', 'port': 80},
            {'host': 'b.example.com', 'port': 443},
          ]);
        },
      ),
    );

    test(
      'invalid nested int in object values item stays in-form',
      () => testNocterm(
        'invalid nested int in values object',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedObjectItemValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          await tester.sendTab(); // host
          await tester.sendTab(); // port
          for (var i = 0; i < '80'.length; i++) {
            await tester.sendBackspace();
          }
          await tester.enterText('x');
          await tester.sendTab();
          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNull);
          expect(
            tester.terminalState.getText(),
            contains('Enter a valid integer'),
          );
        },
      ),
    );

    test(
      'removes a defaulted choice values item and copies option state',
      () => testNocterm(
        'remove choice values item copies state',
        size: const Size(80, 40),
        (tester) async {
          Map<String, Object?>? submitted;
          await tester.pumpComponent(
            CastVariableForm(
              variableGroup: _buildDefaultedChoiceValuesVariableGroup(),
              moldName: 'demo_app',
              moldDescription: 'A demo mold.',
              onSubmit: (values) => submitted = values,
              onCancel: () {},
            ),
          );

          expect(tester.terminalState.getText(), contains('2 items'));
          await tester.sendKey(LogicalKey.keyD);
          await tester.pump();
          expect(tester.terminalState.getText(), contains('1 item'));

          await tester.sendTab();
          await tester.sendEnter();
          await tester.pump();

          expect(submitted, isNotNull);
          expect(submitted!['platforms'], ['android']);
        },
      ),
    );
  });
}
