import 'package:foundry_cli/src/tui/cast_variable_text_parser.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:nocterm/nocterm.dart';

/// {@template foundry_cli.cast_variable_form}
/// A Nocterm-based form that gathers and validates a mold's cast variables.
///
/// Renders one field per visible entry of [variableGroup], recomputing
/// visibility, defaults, and validation as the user edits values. String,
/// int, and double kinds use text fields (with in-form parse feedback for
/// numbers); boolean kinds use a Space-to-toggle control; single- and
/// multiple-choice kinds use option lists driven by ↑/↓ and Space. Submitting
/// the last field with all values valid calls [onSubmit] with the resolved
/// values; pressing Escape calls [onCancel]. This component only gathers
/// values — it does not run the cast pipeline itself.
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
  final Map<String, Object?> _choiceRawValues = {};
  final Map<String, int> _optionCursorByKey = {};
  final Set<String> _dirtyKeys = {};
  int _focusedIndex = 0;
  bool _showErrors = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final collected = _collectRawValues();
    final evaluation = component.variableGroup.evaluate(
      rawValues: collected.rawValues,
      dirtyKeys: _dirtyKeys,
    );
    _syncFieldState(evaluation);
    final validation = component.variableGroup.validate(evaluation);
    final entries = evaluation.entries;

    if (_focusedIndex >= entries.length && entries.isNotEmpty) {
      _focusedIndex = entries.length - 1;
    }

    return Focusable(
      focused: true,
      onKeyEvent: (event) => _handleKeyEvent(
        event,
        entries,
        evaluation,
        validation,
        collected.parseErrors,
      ),
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
                    parseError: collected.parseErrors[entries[index].key],
                    focused: index == _focusedIndex,
                    onSubmitted: () {
                      if (index < entries.length - 1) {
                        setState(() => _focusedIndex = index + 1);
                        return;
                      }
                      _attemptSubmit(
                        evaluation,
                        validation,
                        collected.parseErrors,
                      );
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
                  'Tab/Shift+Tab to move, ↑/↓ for choices, Space toggles, '
                  'Enter on the last field to confirm, Esc to cancel.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({Map<String, Object?> rawValues, Map<String, String> parseErrors})
      _collectRawValues() {
    final rawValues = <String, Object?>{};
    final parseErrors = <String, String>{};

    for (final controllerEntry in _controllers.entries) {
      final key = controllerEntry.key;
      final variable = component.variableGroup.variables[key];
      if (variable == null || _isChoiceVariable(variable)) {
        continue;
      }

      switch (parseCastVariableText(variable, controllerEntry.value.text)) {
        case CastVariableTextParseSuccess(:final value):
          rawValues[key] = value;
        case CastVariableTextParseFailure(:final message):
          rawValues[key] = null;
          parseErrors[key] = message;
      }
    }

    for (final choiceEntry in _choiceRawValues.entries) {
      rawValues[choiceEntry.key] = choiceEntry.value;
    }

    return (rawValues: rawValues, parseErrors: parseErrors);
  }

  bool _handleKeyEvent(
    KeyboardEvent event,
    List<FoundryVariableEvaluationEntry> entries,
    FoundryVariableGroupEvaluation evaluation,
    FoundryVariableGroupValidation validation,
    Map<String, String> parseErrors,
  ) {
    if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
      if (entries.isEmpty) {
        return true;
      }
      setState(() {
        _focusedIndex = (_focusedIndex + 1) % entries.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
      if (entries.isEmpty) {
        return true;
      }
      setState(() {
        _focusedIndex = (_focusedIndex - 1 + entries.length) % entries.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      component.onCancel();
      return true;
    }

    if (entries.isEmpty ||
        _focusedIndex < 0 ||
        _focusedIndex >= entries.length) {
      return false;
    }

    final focusedEntry = entries[_focusedIndex];
    final variable = focusedEntry.variable;

    if (variable is FoundryBooleanVariable) {
      return _handleBooleanKeyEvent(
        event,
        focusedEntry: focusedEntry,
        entries: entries,
        evaluation: evaluation,
        validation: validation,
        parseErrors: parseErrors,
      );
    }

    if (variable is FoundrySingleChoiceVariable ||
        variable is FoundryMultipleChoiceVariable) {
      return _handleChoiceKeyEvent(
        event,
        focusedEntry: focusedEntry,
        entries: entries,
        evaluation: evaluation,
        validation: validation,
        parseErrors: parseErrors,
      );
    }

    return false;
  }

  bool _handleBooleanKeyEvent(
    KeyboardEvent event, {
    required FoundryVariableEvaluationEntry focusedEntry,
    required List<FoundryVariableEvaluationEntry> entries,
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required Map<String, String> parseErrors,
  }) {
    if (event.logicalKey == LogicalKey.space && focusedEntry.isEnabled) {
      setState(() {
        _dirtyKeys.add(focusedEntry.key);
        final controller = _controllers[focusedEntry.key]!;
        final currentlyChecked = focusedEntry.value == true;
        controller.text = (!currentlyChecked).toString();
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.enter) {
      if (_focusedIndex < entries.length - 1) {
        setState(() => _focusedIndex = _focusedIndex + 1);
        return true;
      }
      _attemptSubmit(evaluation, validation, parseErrors);
      return true;
    }

    return false;
  }

  bool _handleChoiceKeyEvent(
    KeyboardEvent event, {
    required FoundryVariableEvaluationEntry focusedEntry,
    required List<FoundryVariableEvaluationEntry> entries,
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required Map<String, String> parseErrors,
  }) {
    final options = _choiceOptions(focusedEntry.variable);
    if (options.isEmpty) {
      if (event.logicalKey == LogicalKey.enter) {
        if (_focusedIndex < entries.length - 1) {
          setState(() => _focusedIndex = _focusedIndex + 1);
          return true;
        }
        _attemptSubmit(evaluation, validation, parseErrors);
        return true;
      }
      return false;
    }

    final cursor = _optionCursorByKey[focusedEntry.key] ?? 0;

    if (event.logicalKey == LogicalKey.arrowUp && focusedEntry.isEnabled) {
      setState(() {
        final nextCursor = (cursor - 1 + options.length) % options.length;
        _optionCursorByKey[focusedEntry.key] = nextCursor;
        if (focusedEntry.variable is FoundrySingleChoiceVariable) {
          _dirtyKeys.add(focusedEntry.key);
          _choiceRawValues[focusedEntry.key] = options[nextCursor];
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.arrowDown && focusedEntry.isEnabled) {
      setState(() {
        final nextCursor = (cursor + 1) % options.length;
        _optionCursorByKey[focusedEntry.key] = nextCursor;
        if (focusedEntry.variable is FoundrySingleChoiceVariable) {
          _dirtyKeys.add(focusedEntry.key);
          _choiceRawValues[focusedEntry.key] = options[nextCursor];
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.space && focusedEntry.isEnabled) {
      setState(() {
        _dirtyKeys.add(focusedEntry.key);
        final option = options[cursor];
        switch (focusedEntry.variable) {
          case FoundrySingleChoiceVariable():
            _choiceRawValues[focusedEntry.key] = option;
          case FoundryMultipleChoiceVariable():
            final current = _selectedOptions(focusedEntry);
            if (current.contains(option)) {
              current.remove(option);
            } else {
              current.add(option);
            }
            _choiceRawValues[focusedEntry.key] = current;
          default:
            break;
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.enter) {
      if (_focusedIndex < entries.length - 1) {
        setState(() => _focusedIndex = _focusedIndex + 1);
        return true;
      }
      _attemptSubmit(evaluation, validation, parseErrors);
      return true;
    }

    return false;
  }

  Component _buildField({
    required FoundryVariableEvaluationEntry entry,
    required List<String> fieldErrors,
    required String? parseError,
    required bool focused,
    required VoidCallback onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.key}: ${entry.variable.label}',
          style: const TextStyle(color: Colors.yellow),
        ),
        if (entry.description != null) Text(entry.description!),
        switch (entry.variable) {
          FoundryBooleanVariable() => _buildBooleanControl(
              entry: entry,
              focused: focused,
            ),
          FoundrySingleChoiceVariable() => _buildSingleChoiceControl(
              entry: entry,
              focused: focused,
            ),
          FoundryMultipleChoiceVariable() => _buildMultipleChoiceControl(
              entry: entry,
              focused: focused,
            ),
          FoundryStringVariable() ||
          FoundryIntVariable() ||
          FoundryDoubleVariable() =>
            _buildTextControl(
              entry: entry,
              focused: focused,
              onSubmitted: onSubmitted,
            ),
        },
        if (entry.help != null)
          Text(entry.help!, style: const TextStyle(color: Colors.gray)),
        if (parseError != null)
          Text(parseError, style: const TextStyle(color: Colors.red)),
        if (_showErrors)
          ...fieldErrors.map(
            (error) => Text(error, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Component _buildBooleanControl({
    required FoundryVariableEvaluationEntry entry,
    required bool focused,
  }) {
    final label = switch (entry.value) {
      null => '[-] unset',
      true => '[x] yes',
      _ => '[ ] no',
    };

    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: focused ? Colors.cyan : Colors.gray,
        ),
      ),
      child: Text(
        entry.isEnabled ? label : '$label (read-only)',
        style: TextStyle(
          color: entry.isEnabled ? null : Colors.gray,
        ),
      ),
    );
  }

  Component _buildSingleChoiceControl({
    required FoundryVariableEvaluationEntry entry,
    required bool focused,
  }) {
    if (entry.variable is! FoundrySingleChoiceVariable) {
      return const SizedBox();
    }

    final choiceUi = _choiceUiParts(entry.variable);
    final options = choiceUi.options;
    final displayLabel = choiceUi.displayLabel;
    final cursor = _optionCursorByKey[entry.key] ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: focused ? Colors.cyan : Colors.gray,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < options.length; index++)
            Text(
              _formatChoiceOptionLine(
                marker: entry.value == options[index] ? '(•)' : '( )',
                label: _choiceDisplayLabel(displayLabel, options[index]),
                showCursor: focused && entry.isEnabled && index == cursor,
                enabled: entry.isEnabled,
              ),
              style: TextStyle(
                color: entry.isEnabled ? null : Colors.gray,
              ),
            ),
          if (!entry.isEnabled)
            const Text(
              '(read-only)',
              style: TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }

  Component _buildMultipleChoiceControl({
    required FoundryVariableEvaluationEntry entry,
    required bool focused,
  }) {
    if (entry.variable is! FoundryMultipleChoiceVariable) {
      return const SizedBox();
    }

    final choiceUi = _choiceUiParts(entry.variable);
    final options = choiceUi.options;
    final displayLabel = choiceUi.displayLabel;
    final cursor = _optionCursorByKey[entry.key] ?? 0;
    final selected = _selectedOptions(entry).toSet();

    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: focused ? Colors.cyan : Colors.gray,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < options.length; index++)
            Text(
              _formatChoiceOptionLine(
                marker: selected.contains(options[index]) ? '[x]' : '[ ]',
                label: _choiceDisplayLabel(displayLabel, options[index]),
                showCursor: focused && entry.isEnabled && index == cursor,
                enabled: entry.isEnabled,
              ),
              style: TextStyle(
                color: entry.isEnabled ? null : Colors.gray,
              ),
            ),
          if (!entry.isEnabled)
            const Text(
              '(read-only)',
              style: TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }

  /// Invokes a choice [displayLabel] without requiring `T` == `dynamic`.
  String _choiceDisplayLabel(Function displayLabel, Object? option) {
    return Function.apply(displayLabel, [option]) as String;
  }

  /// Reads choice options/labels without viewing the variable as `<dynamic>`.
  ///
  /// A typed `FoundrySingleChoiceVariable<String>` exposed as
  /// `FoundrySingleChoiceVariable<dynamic>` rejects its own
  /// `String Function(String)` displayLabel callback at runtime.
  ({List<Object?> options, Function displayLabel}) _choiceUiParts(
    FoundryVariable<dynamic> variable,
  ) {
    final dynamic choice = variable;
    // Keep concrete displayLabel function types (avoid `<dynamic>` view).
    // ignore: avoid_dynamic_calls
    final options = List<Object?>.from(choice.options as List);
    // Keep concrete displayLabel function types (avoid `<dynamic>` view).
    // ignore: avoid_dynamic_calls
    final displayLabel = choice.displayLabel as Function;
    return (options: options, displayLabel: displayLabel);
  }

  String _formatChoiceOptionLine({
    required String marker,
    required String label,
    required bool showCursor,
    required bool enabled,
  }) {
    final prefix = showCursor && enabled ? '>' : ' ';
    return '$prefix $marker $label';
  }

  Component _buildTextControl({
    required FoundryVariableEvaluationEntry entry,
    required bool focused,
    required VoidCallback onSubmitted,
  }) {
    final controller = _controllers[entry.key]!;

    return Container(
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
    );
  }

  void _syncFieldState(FoundryVariableGroupEvaluation evaluation) {
    final activeKeys = evaluation.entries.map((entry) => entry.key).toSet();

    for (final entry in evaluation.entries) {
      final variable = entry.variable;
      if (_isChoiceVariable(variable)) {
        if (!_dirtyKeys.contains(entry.key)) {
          _choiceRawValues[entry.key] = entry.value;
        }

        final options = _choiceOptions(variable);
        _optionCursorByKey.putIfAbsent(entry.key, () {
          if (variable is! FoundrySingleChoiceVariable) {
            return 0;
          }
          final selectedIndex = options.indexOf(entry.value);
          return selectedIndex >= 0 ? selectedIndex : 0;
        });
        final cursor = _optionCursorByKey[entry.key]!;
        _optionCursorByKey[entry.key] =
            options.isEmpty ? 0 : cursor % options.length;
        continue;
      }

      final displayValue = switch (variable) {
        FoundryBooleanVariable() =>
          entry.value == null ? '' : (entry.value == true).toString(),
        _ => entry.value?.toString() ?? '',
      };
      final controller = _controllers.putIfAbsent(
        entry.key,
        TextEditingController.new,
      );

      if (!_dirtyKeys.contains(entry.key) && controller.text != displayValue) {
        controller.text = displayValue;
      }
    }

    final removedControllerKeys =
        _controllers.keys.where((key) => !activeKeys.contains(key)).toList();
    for (final key in removedControllerKeys) {
      _controllers.remove(key)?.dispose();
      _dirtyKeys.remove(key);
    }

    final removedChoiceKeys = _choiceRawValues.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in removedChoiceKeys) {
      _choiceRawValues.remove(key);
      _dirtyKeys.remove(key);
    }

    _optionCursorByKey.removeWhere((key, _) => !activeKeys.contains(key));
  }

  List<Object?> _choiceOptions(FoundryVariable<dynamic> variable) {
    return switch (variable) {
      FoundrySingleChoiceVariable(:final options) =>
        List<Object?>.from(options),
      FoundryMultipleChoiceVariable(:final options) =>
        List<Object?>.from(options),
      _ => const <Object?>[],
    };
  }

  List<Object?> _selectedOptions(FoundryVariableEvaluationEntry entry) {
    final raw = _choiceRawValues[entry.key] ?? entry.value;
    if (raw is! List) {
      return <Object?>[];
    }
    return List<Object?>.from(raw);
  }

  bool _isChoiceVariable(FoundryVariable<dynamic> variable) {
    return variable is FoundrySingleChoiceVariable ||
        variable is FoundryMultipleChoiceVariable;
  }

  void _attemptSubmit(
    FoundryVariableGroupEvaluation evaluation,
    FoundryVariableGroupValidation validation,
    Map<String, String> parseErrors,
  ) {
    if (parseErrors.isNotEmpty || !validation.isValid) {
      setState(() => _showErrors = true);
      return;
    }
    component.onSubmit(evaluation.resolvedValues);
  }
}
