import 'package:foundry_core/foundry_core.dart';
import 'package:nocterm/nocterm.dart';

/// {@template foundry_cli.cast_variable_form}
/// A Nocterm-based form that gathers and validates a mold's cast variables.
///
/// Renders one field per visible entry of [variableGroup], recomputing
/// visibility, defaults, and validation as the user edits values (see
/// REQUIREMENTS.md §5.4). Submitting the last field with all values valid
/// calls [onSubmit] with the resolved values; pressing Escape calls
/// [onCancel]. This component only gathers values — it does not run the
/// cast pipeline itself.
/// {@endtemplate}
class CastVariableForm extends StatefulComponent {
  /// {@macro foundry_cli.cast_variable_form}
  const CastVariableForm({
    required this.variableGroup,
    required this.moldName,
    required this.moldDescription,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  /// The mold's variable schema loaded from `variables.dart`.
  final FoundryVariableGroup variableGroup;

  /// Shown in the form header.
  final String moldName;

  /// Shown in the form header.
  final String moldDescription;

  /// Called with the resolved, validated values once the user confirms the
  /// last field.
  final void Function(Map<String, Object?> values) onSubmit;

  /// Called when the user cancels the form (Escape).
  final VoidCallback onCancel;

  @override
  State<CastVariableForm> createState() => _CastVariableFormState();
}

class _CastVariableFormState extends State<CastVariableForm> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _dirtyKeys = {};
  int _focusedIndex = 0;
  bool _showErrors = false;

  Map<String, Object?> get _rawValues => {
        for (final entry in _controllers.entries) entry.key: entry.value.text,
      };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final evaluation = component.variableGroup.evaluate(
      rawValues: _rawValues,
      dirtyKeys: _dirtyKeys,
    );
    _syncControllers(evaluation);
    final validation = component.variableGroup.validate(evaluation);
    final entries = evaluation.entries;

    if (_focusedIndex >= entries.length && entries.isNotEmpty) {
      _focusedIndex = entries.length - 1;
    }

    return Focusable(
      focused: true,
      onKeyEvent: (event) => _handleKeyEvent(event, entries.length),
      child: Container(
        padding: const EdgeInsets.all(1),
        // The form's contents live in a single [Column] child so that the
        // enclosing [ListView] only ever diffs one (freshly built) child.
        // Nocterm's `ListView` re-`update`s cached children in place and
        // asserts the new component differs from the old one, which breaks
        // for canonicalized `const` children reused across rebuilds. `Column`
        // diffs its children safely, so nesting keeps the `const` literals.
        child: ListView(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FOUNDRY // ${component.moldName}',
                  style: const TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(component.moldDescription),
                const SizedBox(height: 1),
                for (var index = 0; index < entries.length; index++) ...[
                  _buildField(
                    entry: entries[index],
                    fieldErrors:
                        validation.fieldErrors[entries[index].key] ?? const [],
                    focused: index == _focusedIndex,
                    onSubmitted: () {
                      if (index < entries.length - 1) {
                        setState(() => _focusedIndex = index + 1);
                        return;
                      }
                      _attemptSubmit(evaluation, validation);
                    },
                  ),
                  const SizedBox(height: 1),
                ],
                if (_showErrors && validation.groupErrors.isNotEmpty)
                  ...validation.groupErrors.map(
                    (error) => Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const Text(
                  'Tab/Shift+Tab to move, Enter on the last field to confirm, '
                  'Esc to cancel.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _handleKeyEvent(KeyboardEvent event, int entryCount) {
    if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
      setState(() {
        if (entryCount > 0) {
          _focusedIndex = (_focusedIndex + 1) % entryCount;
        }
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
      setState(() {
        if (entryCount > 0) {
          _focusedIndex = (_focusedIndex - 1 + entryCount) % entryCount;
        }
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      component.onCancel();
      return true;
    }
    return false;
  }

  Component _buildField({
    required FoundryVariableEvaluationEntry entry,
    required List<String> fieldErrors,
    required bool focused,
    required VoidCallback onSubmitted,
  }) {
    final controller = _controllers[entry.key]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.key}: ${entry.variable.label}',
          style: const TextStyle(color: Colors.yellow),
        ),
        if (entry.description != null) Text(entry.description!),
        Container(
          decoration: BoxDecoration(
            border: BoxBorder.all(
              color: focused ? Colors.cyan : Colors.gray,
            ),
          ),
          child: TextField(
            controller: controller,
            focused: focused,
            enabled: entry.isEnabled,
            readOnly: !entry.isEnabled,
            width: 72,
            height: 1,
            placeholder: entry.placeholder ?? 'Enter ${entry.key}',
            onChanged: (value) {
              setState(() => _dirtyKeys.add(entry.key));
            },
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        if (entry.help != null)
          Text(entry.help!, style: const TextStyle(color: Colors.gray)),
        if (_showErrors)
          ...fieldErrors.map(
            (error) => Text(error, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  void _syncControllers(FoundryVariableGroupEvaluation evaluation) {
    final activeKeys = evaluation.entries.map((entry) => entry.key).toSet();

    for (final entry in evaluation.entries) {
      final displayValue = entry.value?.toString() ?? '';
      final controller = _controllers.putIfAbsent(
        entry.key,
        TextEditingController.new,
      );

      if (!_dirtyKeys.contains(entry.key) && controller.text != displayValue) {
        controller.text = displayValue;
      }
    }

    final removedKeys =
        _controllers.keys.where((key) => !activeKeys.contains(key)).toList();
    for (final key in removedKeys) {
      _controllers.remove(key)?.dispose();
      _dirtyKeys.remove(key);
    }
  }

  void _attemptSubmit(
    FoundryVariableGroupEvaluation evaluation,
    FoundryVariableGroupValidation validation,
  ) {
    if (!validation.isValid) {
      setState(() => _showErrors = true);
      return;
    }
    component.onSubmit(evaluation.resolvedValues);
  }
}
