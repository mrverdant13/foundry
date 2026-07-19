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
/// multiple-choice kinds use option lists driven by ↑/↓ and Space; object
/// kinds render nested sections recursively with the same field widgets.
/// Submitting the last field with all values valid calls [onSubmit] with the
/// resolved values; pressing Escape calls [onCancel]. This component only
/// gathers values — it does not run the cast pipeline itself.
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
  static const _pathSeparator = '\u001f';

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
    _reconcileFieldKinds();
    final collected = _collectRawValues();
    final evaluation = component.variableGroup.evaluate(
      rawValues: collected.rawValues,
      dirtyKeys: collected.topLevelDirtyKeys,
    );
    final focusTargets = _buildFocusTargets(
      evaluation: evaluation,
      rawValues: collected.rawValues,
    );
    _syncFieldState(focusTargets);
    final validation = component.variableGroup.validate(evaluation);

    if (_focusedIndex >= focusTargets.length && focusTargets.isNotEmpty) {
      _focusedIndex = focusTargets.length - 1;
    }

    return Focusable(
      focused: true,
      onKeyEvent: (event) => _handleKeyEvent(
        event,
        focusTargets,
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
                ..._buildGroupFields(
                  evaluation: evaluation,
                  validation: validation,
                  rootEvaluation: evaluation,
                  rootValidation: validation,
                  rawValues: collected.rawValues,
                  parseErrors: collected.parseErrors,
                  pathPrefix: const [],
                  ancestorsEnabled: true,
                  focusTargets: focusTargets,
                  depth: 0,
                ),
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

  List<Component> _buildGroupFields({
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required FoundryVariableGroupEvaluation rootEvaluation,
    required FoundryVariableGroupValidation rootValidation,
    required Map<String, Object?> rawValues,
    required Map<String, String> parseErrors,
    required List<String> pathPrefix,
    required bool ancestorsEnabled,
    required List<_FocusTarget> focusTargets,
    required int depth,
  }) {
    final children = <Component>[];
    for (final entry in evaluation.entries) {
      final path = [...pathPrefix, entry.key];
      final pathKey = _joinPath(path);
      final effectiveEnabled = ancestorsEnabled && entry.isEnabled;

      if (entry.variable is FoundryObjectVariable) {
        final objectVariable = entry.variable as FoundryObjectVariable;
        final nestedRaw = _nestedRawMap(rawValues, path) ?? const {};
        final nestedEvaluation = objectVariable.group.evaluate(
          rawValues: nestedRaw,
        );
        final nestedValidation = objectVariable.group.validate(
          nestedEvaluation,
        );

        children
          ..add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'  ' * depth}${entry.key}: ${entry.variable.label}',
                  style: const TextStyle(color: Colors.yellow),
                ),
                if (entry.description != null)
                  Text('${'  ' * depth}${entry.description!}'),
                if (entry.help != null)
                  Text(
                    '${'  ' * depth}${entry.help!}',
                    style: const TextStyle(color: Colors.gray),
                  ),
                if (!effectiveEnabled)
                  Text(
                    '${'  ' * depth}(read-only)',
                    style: const TextStyle(color: Colors.gray),
                  ),
                if (_showErrors) ...[
                  ...nestedValidation.groupErrors.map(
                    (error) => Text(
                      '${'  ' * depth}$error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  // Object-level validators (and remaining flattened errors)
                  // surface on the section when submit is attempted.
                  ...(validation.fieldErrors[entry.key] ?? const [])
                      .where(
                        (error) => !nestedValidation.fieldErrors.keys.any(
                          (nestedKey) => error.startsWith('$nestedKey: '),
                        ),
                      )
                      .where(
                        (error) =>
                            !nestedValidation.groupErrors.contains(error),
                      )
                      .map(
                        (error) => Text(
                          '${'  ' * depth}$error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                ],
                ..._buildGroupFields(
                  evaluation: nestedEvaluation,
                  validation: nestedValidation,
                  rootEvaluation: rootEvaluation,
                  rootValidation: rootValidation,
                  rawValues: rawValues,
                  parseErrors: parseErrors,
                  pathPrefix: path,
                  ancestorsEnabled: effectiveEnabled,
                  focusTargets: focusTargets,
                  depth: depth + 1,
                ),
              ],
            ),
          )
          ..add(const SizedBox(height: 1));
        continue;
      }

      final focusIndex = focusTargets.indexWhere(
        (target) => target.pathKey == pathKey,
      );
      final focused = focusIndex >= 0 && focusIndex == _focusedIndex;
      final fieldErrors = validation.fieldErrors[entry.key] ?? const [];

      children
        ..add(
          _buildField(
            entry: entry,
            pathKey: pathKey,
            fieldErrors: fieldErrors,
            parseError: parseErrors[pathKey],
            focused: focused,
            effectiveEnabled: effectiveEnabled,
            depth: depth,
            onSubmitted: () {
              if (focusIndex < 0) {
                return;
              }
              if (focusIndex < focusTargets.length - 1) {
                setState(() => _focusedIndex = focusIndex + 1);
                return;
              }
              _attemptSubmit(rootEvaluation, rootValidation, parseErrors);
            },
          ),
        )
        ..add(const SizedBox(height: 1));
    }
    return children;
  }

  ({
    Map<String, Object?> rawValues,
    Map<String, String> parseErrors,
    Set<String> topLevelDirtyKeys,
  }) _collectRawValues() {
    final rawValues = <String, Object?>{};
    final parseErrors = <String, String>{};

    for (final controllerEntry in _controllers.entries) {
      final pathKey = controllerEntry.key;
      final path = _splitPath(pathKey);
      final variable = _variableAtPath(component.variableGroup, path);
      if (variable == null ||
          _isChoiceVariable(variable) ||
          variable is FoundryObjectVariable) {
        continue;
      }

      // Top-level scalars always contribute controller text. Nested scalars
      // only contribute when dirty so omitted nested keys can recompute
      // defaults (and explicit nested nulls stay meaningful once dirty).
      final includeRaw = path.length == 1 || _dirtyKeys.contains(pathKey);

      switch (parseCastVariableText(variable, controllerEntry.value.text)) {
        case CastVariableTextParseSuccess(:final value):
          if (includeRaw) {
            _setAtPath(rawValues, path, value);
          }
        case CastVariableTextParseFailure(:final message):
          if (includeRaw) {
            _setAtPath(rawValues, path, null);
          }
          parseErrors[pathKey] = message;
      }
    }

    for (final choiceEntry in _choiceRawValues.entries) {
      final pathKey = choiceEntry.key;
      final path = _splitPath(pathKey);
      final variable = _variableAtPath(component.variableGroup, path);
      if (variable == null || !_isChoiceVariable(variable)) {
        continue;
      }
      // Only dirty choice values are raw input. Non-dirty cached values must
      // not pin defaults, or dependent defaultValue callbacks cannot recompute.
      if (!_dirtyKeys.contains(pathKey)) {
        continue;
      }
      _setAtPath(rawValues, path, choiceEntry.value);
    }

    return (
      rawValues: rawValues,
      parseErrors: parseErrors,
      topLevelDirtyKeys: _topLevelDirtyKeys(),
    );
  }

  Set<String> _topLevelDirtyKeys() {
    return {
      for (final pathKey in _dirtyKeys) _splitPath(pathKey).first,
    };
  }

  bool _handleKeyEvent(
    KeyboardEvent event,
    List<_FocusTarget> focusTargets,
    FoundryVariableGroupEvaluation evaluation,
    FoundryVariableGroupValidation validation,
    Map<String, String> parseErrors,
  ) {
    if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
      if (focusTargets.isEmpty) {
        return true;
      }
      setState(() {
        _focusedIndex = (_focusedIndex + 1) % focusTargets.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
      if (focusTargets.isEmpty) {
        return true;
      }
      setState(() {
        _focusedIndex =
            (_focusedIndex - 1 + focusTargets.length) % focusTargets.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      component.onCancel();
      return true;
    }

    if (focusTargets.isEmpty ||
        _focusedIndex < 0 ||
        _focusedIndex >= focusTargets.length) {
      return false;
    }

    final focusedTarget = focusTargets[_focusedIndex];
    final variable = focusedTarget.entry.variable;

    if (variable is FoundryBooleanVariable) {
      return _handleBooleanKeyEvent(
        event,
        focusedTarget: focusedTarget,
        focusTargets: focusTargets,
        evaluation: evaluation,
        validation: validation,
        parseErrors: parseErrors,
      );
    }

    if (variable is FoundrySingleChoiceVariable ||
        variable is FoundryMultipleChoiceVariable) {
      return _handleChoiceKeyEvent(
        event,
        focusedTarget: focusedTarget,
        focusTargets: focusTargets,
        evaluation: evaluation,
        validation: validation,
        parseErrors: parseErrors,
      );
    }

    return false;
  }

  bool _handleBooleanKeyEvent(
    KeyboardEvent event, {
    required _FocusTarget focusedTarget,
    required List<_FocusTarget> focusTargets,
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required Map<String, String> parseErrors,
  }) {
    if (event.logicalKey == LogicalKey.space && focusedTarget.isEnabled) {
      setState(() {
        _dirtyKeys.add(focusedTarget.pathKey);
        final controller = _controllers[focusedTarget.pathKey]!;
        final currentlyChecked = focusedTarget.entry.value == true;
        controller.text = (!currentlyChecked).toString();
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.enter) {
      if (_focusedIndex < focusTargets.length - 1) {
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
    required _FocusTarget focusedTarget,
    required List<_FocusTarget> focusTargets,
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required Map<String, String> parseErrors,
  }) {
    final options = _choiceOptions(focusedTarget.entry.variable);
    if (options.isEmpty) {
      if (event.logicalKey == LogicalKey.enter) {
        if (_focusedIndex < focusTargets.length - 1) {
          setState(() => _focusedIndex = _focusedIndex + 1);
          return true;
        }
        _attemptSubmit(evaluation, validation, parseErrors);
        return true;
      }
      return false;
    }

    final cursor = _optionCursorByKey[focusedTarget.pathKey] ?? 0;

    if (event.logicalKey == LogicalKey.arrowUp && focusedTarget.isEnabled) {
      setState(() {
        final nextCursor = (cursor - 1 + options.length) % options.length;
        _optionCursorByKey[focusedTarget.pathKey] = nextCursor;
        if (focusedTarget.entry.variable is FoundrySingleChoiceVariable) {
          _dirtyKeys.add(focusedTarget.pathKey);
          _choiceRawValues[focusedTarget.pathKey] = options[nextCursor];
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.arrowDown && focusedTarget.isEnabled) {
      setState(() {
        final nextCursor = (cursor + 1) % options.length;
        _optionCursorByKey[focusedTarget.pathKey] = nextCursor;
        if (focusedTarget.entry.variable is FoundrySingleChoiceVariable) {
          _dirtyKeys.add(focusedTarget.pathKey);
          _choiceRawValues[focusedTarget.pathKey] = options[nextCursor];
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.space && focusedTarget.isEnabled) {
      setState(() {
        _dirtyKeys.add(focusedTarget.pathKey);
        final option = options[cursor];
        switch (focusedTarget.entry.variable) {
          case FoundrySingleChoiceVariable():
            _choiceRawValues[focusedTarget.pathKey] = option;
          case FoundryMultipleChoiceVariable():
            final current = _selectedOptions(focusedTarget);
            if (current.contains(option)) {
              current.remove(option);
            } else {
              current.add(option);
            }
            _choiceRawValues[focusedTarget.pathKey] = current;
          default:
            break;
        }
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.enter) {
      if (_focusedIndex < focusTargets.length - 1) {
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
    required String pathKey,
    required List<String> fieldErrors,
    required String? parseError,
    required bool focused,
    required bool effectiveEnabled,
    required int depth,
    required VoidCallback onSubmitted,
  }) {
    final indent = '  ' * depth;
    final enabledEntry = FoundryVariableEvaluationEntry(
      key: entry.key,
      variable: entry.variable,
      value: entry.value,
      isEnabled: effectiveEnabled,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$indent${entry.key}: ${entry.variable.label}',
          style: const TextStyle(color: Colors.yellow),
        ),
        if (entry.description != null) Text('$indent${entry.description!}'),
        _buildLeafControl(
          entry: enabledEntry,
          pathKey: pathKey,
          focused: focused,
          onSubmitted: onSubmitted,
        ),
        if (entry.help != null)
          Text(
            '$indent${entry.help!}',
            style: const TextStyle(color: Colors.gray),
          ),
        if (parseError != null)
          Text(
            '$indent$parseError',
            style: const TextStyle(color: Colors.red),
          ),
        if (_showErrors)
          ...fieldErrors.map(
            (error) => Text(
              '$indent$error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  /// Builds the interactive control for a non-object leaf field.
  ///
  /// Object variables are rendered as sections in [_buildGroupFields] and never
  /// reach this helper.
  Component _buildLeafControl({
    required FoundryVariableEvaluationEntry entry,
    required String pathKey,
    required bool focused,
    required VoidCallback onSubmitted,
  }) {
    final variable = entry.variable;
    if (variable is FoundryBooleanVariable) {
      return _buildBooleanControl(entry: entry, focused: focused);
    }
    if (variable is FoundrySingleChoiceVariable) {
      return _buildSingleChoiceControl(
        entry: entry,
        pathKey: pathKey,
        focused: focused,
      );
    }
    if (variable is FoundryMultipleChoiceVariable) {
      return _buildMultipleChoiceControl(
        entry: entry,
        pathKey: pathKey,
        focused: focused,
      );
    }
    return _buildTextControl(
      entry: entry,
      pathKey: pathKey,
      focused: focused,
      onSubmitted: onSubmitted,
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
    required String pathKey,
    required bool focused,
  }) {
    if (entry.variable is! FoundrySingleChoiceVariable) {
      return const SizedBox();
    }

    final choiceUi = _choiceUiParts(entry.variable);
    final options = choiceUi.options;
    final displayLabel = choiceUi.displayLabel;
    final cursor = _optionCursorByKey[pathKey] ?? 0;

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
    required String pathKey,
    required bool focused,
  }) {
    if (entry.variable is! FoundryMultipleChoiceVariable) {
      return const SizedBox();
    }

    final choiceUi = _choiceUiParts(entry.variable);
    final options = choiceUi.options;
    final displayLabel = choiceUi.displayLabel;
    final cursor = _optionCursorByKey[pathKey] ?? 0;
    final selected = _selectedOptionsForPath(pathKey, entry).toSet();

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
    required String pathKey,
    required bool focused,
    required VoidCallback onSubmitted,
  }) {
    final controller = _controllers[pathKey]!;

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
          setState(() => _dirtyKeys.add(pathKey));
        },
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }

  List<_FocusTarget> _buildFocusTargets({
    required FoundryVariableGroupEvaluation evaluation,
    required Map<String, Object?> rawValues,
    List<String> pathPrefix = const [],
    bool ancestorsEnabled = true,
  }) {
    final targets = <_FocusTarget>[];
    for (final entry in evaluation.entries) {
      final path = [...pathPrefix, entry.key];
      final pathKey = _joinPath(path);
      final isEnabled = ancestorsEnabled && entry.isEnabled;

      if (entry.variable is FoundryObjectVariable) {
        final objectVariable = entry.variable as FoundryObjectVariable;
        final nestedRaw = _nestedRawMap(rawValues, path) ?? const {};
        final nestedEvaluation = objectVariable.group.evaluate(
          rawValues: nestedRaw,
        );
        targets.addAll(
          _buildFocusTargets(
            evaluation: nestedEvaluation,
            rawValues: rawValues,
            pathPrefix: path,
            ancestorsEnabled: isEnabled,
          ),
        );
        continue;
      }

      targets.add(
        _FocusTarget(
          pathKey: pathKey,
          entry: entry,
          isEnabled: isEnabled,
        ),
      );
    }
    return targets;
  }

  void _syncFieldState(List<_FocusTarget> focusTargets) {
    final activeKeys = focusTargets.map((target) => target.pathKey).toSet();

    for (final target in focusTargets) {
      final entry = target.entry;
      final variable = entry.variable;
      final pathKey = target.pathKey;

      if (_isChoiceVariable(variable)) {
        _clearTextFieldState(pathKey);

        final options = _choiceOptions(variable);
        if (!_dirtyKeys.contains(pathKey)) {
          _choiceRawValues[pathKey] = entry.value;
          if (variable is FoundrySingleChoiceVariable) {
            final selectedIndex = options.indexOf(entry.value);
            _optionCursorByKey[pathKey] =
                options.isEmpty ? 0 : (selectedIndex >= 0 ? selectedIndex : 0);
          } else {
            final cursor = _optionCursorByKey[pathKey] ?? 0;
            _optionCursorByKey[pathKey] =
                options.isEmpty ? 0 : cursor % options.length;
          }
        } else {
          final cursor = _optionCursorByKey[pathKey] ?? 0;
          _optionCursorByKey[pathKey] =
              options.isEmpty ? 0 : cursor % options.length;
        }
        continue;
      }

      _clearChoiceFieldState(pathKey);

      final displayValue = switch (variable) {
        FoundryBooleanVariable() =>
          entry.value == null ? '' : (entry.value == true).toString(),
        _ => entry.value?.toString() ?? '',
      };
      final controller = _controllers.putIfAbsent(
        pathKey,
        TextEditingController.new,
      );

      if (!_dirtyKeys.contains(pathKey) && controller.text != displayValue) {
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

  /// Drops text/choice state that no longer matches each key's current kind.
  ///
  /// Runs before raw-value collection so a schema change cannot leave a stale
  /// dirty flag or raw value that would skew evaluation for the new kind.
  void _reconcileFieldKinds() {
    final keys = <String>{
      ..._controllers.keys,
      ..._choiceRawValues.keys,
      ..._optionCursorByKey.keys,
    };
    for (final key in keys) {
      final variable = _variableAtPath(
        component.variableGroup,
        _splitPath(key),
      );
      if (variable == null) {
        continue;
      }
      if (variable is FoundryObjectVariable) {
        _clearTextFieldState(key);
        _clearChoiceFieldState(key);
        continue;
      }
      if (_isChoiceVariable(variable)) {
        _clearTextFieldState(key);
      } else {
        _clearChoiceFieldState(key);
      }
    }
  }

  void _clearTextFieldState(String key) {
    if (!_controllers.containsKey(key)) {
      return;
    }
    _controllers.remove(key)?.dispose();
    _dirtyKeys.remove(key);
  }

  void _clearChoiceFieldState(String key) {
    if (!_choiceRawValues.containsKey(key) &&
        !_optionCursorByKey.containsKey(key)) {
      return;
    }
    _choiceRawValues.remove(key);
    _optionCursorByKey.remove(key);
    _dirtyKeys.remove(key);
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

  List<Object?> _selectedOptions(_FocusTarget target) {
    return _selectedOptionsForPath(target.pathKey, target.entry);
  }

  List<Object?> _selectedOptionsForPath(
    String pathKey,
    FoundryVariableEvaluationEntry entry,
  ) {
    final raw = _choiceRawValues[pathKey] ?? entry.value;
    if (raw is! List) {
      return <Object?>[];
    }
    return List<Object?>.from(raw);
  }

  bool _isChoiceVariable(FoundryVariable<dynamic> variable) {
    return variable is FoundrySingleChoiceVariable ||
        variable is FoundryMultipleChoiceVariable;
  }

  FoundryVariable<dynamic>? _variableAtPath(
    FoundryVariableGroup group,
    List<String> path,
  ) {
    if (path.isEmpty) {
      return null;
    }

    var currentGroup = group;
    for (var index = 0; index < path.length; index++) {
      final variable = currentGroup.variables[path[index]];
      if (variable == null) {
        return null;
      }
      if (index == path.length - 1) {
        return variable;
      }
      if (variable is! FoundryObjectVariable) {
        return null;
      }
      currentGroup = variable.group;
    }
    return null;
  }

  Map<String, Object?>? _nestedRawMap(
    Map<String, Object?> rawValues,
    List<String> path,
  ) {
    Object? current = rawValues;
    for (final segment in path) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }
    if (current is! Map) {
      return null;
    }
    return {
      for (final entry in current.entries) entry.key.toString(): entry.value,
    };
  }

  void _setAtPath(
    Map<String, Object?> rawValues,
    List<String> path,
    Object? value,
  ) {
    if (path.isEmpty) {
      return;
    }
    if (path.length == 1) {
      rawValues[path.first] = value;
      return;
    }

    final rootKey = path.first;
    final existing = rawValues[rootKey];
    final nested = existing is Map
        ? Map<String, Object?>.from(
            {
              for (final entry in existing.entries)
                entry.key.toString(): entry.value,
            },
          )
        : <String, Object?>{};
    _setAtPath(nested, path.sublist(1), value);
    rawValues[rootKey] = nested;
  }

  String _joinPath(List<String> path) => path.join(_pathSeparator);

  List<String> _splitPath(String pathKey) => pathKey.split(_pathSeparator);

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

class _FocusTarget {
  const _FocusTarget({
    required this.pathKey,
    required this.entry,
    required this.isEnabled,
  });

  final String pathKey;
  final FoundryVariableEvaluationEntry entry;
  final bool isEnabled;
}
