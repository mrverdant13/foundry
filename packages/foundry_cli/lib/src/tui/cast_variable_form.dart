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
/// kinds render nested sections recursively with the same field widgets;
/// values kinds render a list editor (add / remove / reorder) that reuses
/// the item-kind widgets for each element.
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
  final Map<String, int> _valuesLengths = {};
  final Map<String, int> _valuesCursors = {};
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
    var collected = _collectRawValues();
    var evaluation = component.variableGroup.evaluate(
      rawValues: collected.rawValues,
      dirtyKeys: collected.topLevelDirtyKeys,
    );
    _syncValuesListState(
      evaluation,
      pathPrefix: const [],
      rawValues: collected.rawValues,
    );
    if (_needsValuesRecollect(collected.rawValues)) {
      collected = _collectRawValues();
      evaluation = component.variableGroup.evaluate(
        rawValues: collected.rawValues,
        dirtyKeys: collected.topLevelDirtyKeys,
      );
    }
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
                  'Tab/Shift+Tab to move, ↑/↓ for choices/lists, Space toggles, '
                  'a/d add/remove list items, Shift+↑/↓ or k/j reorder, '
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

      if (entry.variable is FoundryValuesVariable) {
        children
          ..add(
            _buildValuesSection(
              entry: entry,
              path: path,
              pathKey: pathKey,
              effectiveEnabled: effectiveEnabled,
              validation: validation,
              rootEvaluation: rootEvaluation,
              rootValidation: rootValidation,
              rawValues: rawValues,
              parseErrors: parseErrors,
              focusTargets: focusTargets,
              depth: depth,
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

  Component _buildValuesSection({
    required FoundryVariableEvaluationEntry entry,
    required List<String> path,
    required String pathKey,
    required bool effectiveEnabled,
    required FoundryVariableGroupValidation validation,
    required FoundryVariableGroupEvaluation rootEvaluation,
    required FoundryVariableGroupValidation rootValidation,
    required Map<String, Object?> rawValues,
    required Map<String, String> parseErrors,
    required List<_FocusTarget> focusTargets,
    required int depth,
  }) {
    final valuesVariable = entry.variable as FoundryValuesVariable;
    final length = _valuesLengths[pathKey] ?? 0;
    final cursor = _valuesCursors[pathKey] ?? 0;
    final listChromeFocusIndex = focusTargets.indexWhere(
      (target) => target.pathKey == pathKey,
    );
    final listChromeFocused =
        listChromeFocusIndex >= 0 && listChromeFocusIndex == _focusedIndex;
    final resolvedList =
        entry.value is List ? entry.value! as List : const <Object?>[];
    final sectionChildren = <Component>[
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
      _buildValuesListChrome(
        length: length,
        cursor: cursor,
        focused: listChromeFocused,
        effectiveEnabled: effectiveEnabled,
        depth: depth,
      ),
      if (_showErrors)
        ...(validation.fieldErrors[entry.key] ?? const [])
            .where((error) => !_isIndexedListError(error))
            .map(
              (error) => Text(
                '${'  ' * depth}$error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
    ];

    for (var index = 0; index < length; index++) {
      final itemPath = [...path, '$index'];
      final itemPathKey = _joinPath(itemPath);
      final itemVariable = valuesVariable.item;
      final itemValue =
          index < resolvedList.length ? resolvedList[index] : null;

      if (itemVariable is FoundryObjectVariable) {
        final nestedRaw = _valueAtPath(rawValues, itemPath);
        final nestedMap = _asStringKeyedMap(nestedRaw) ??
            _asStringKeyedMap(itemValue) ??
            const <String, Object?>{};
        final nestedEvaluation = itemVariable.group.evaluate(
          rawValues: nestedMap,
        );
        final nestedValidation = itemVariable.group.validate(
          nestedEvaluation,
        );

        sectionChildren
          ..add(
            Text(
              '${'  ' * (depth + 1)}[$index]',
              style: TextStyle(
                color: listChromeFocused && cursor == index && effectiveEnabled
                    ? Colors.cyan
                    : Colors.yellow,
              ),
            ),
          )
          ..addAll(
            _buildGroupFields(
              evaluation: nestedEvaluation,
              validation: nestedValidation,
              rootEvaluation: rootEvaluation,
              rootValidation: rootValidation,
              rawValues: rawValues,
              parseErrors: parseErrors,
              pathPrefix: itemPath,
              ancestorsEnabled: effectiveEnabled,
              focusTargets: focusTargets,
              depth: depth + 2,
            ),
          );
        continue;
      }

      final itemEntry = FoundryVariableEvaluationEntry(
        key: '$index',
        variable: itemVariable,
        value: itemValue,
        isEnabled: effectiveEnabled,
      );
      final focusIndex = focusTargets.indexWhere(
        (target) => target.pathKey == itemPathKey,
      );
      final focused = focusIndex >= 0 && focusIndex == _focusedIndex;
      final itemErrors = (validation.fieldErrors[entry.key] ?? const [])
          .where((error) => error.startsWith('[$index]: '))
          .map((error) => error.substring('[$index]: '.length))
          .toList(growable: false);

      sectionChildren.add(
        _buildField(
          entry: itemEntry,
          pathKey: itemPathKey,
          fieldErrors: itemErrors,
          parseError: parseErrors[itemPathKey],
          focused: focused,
          effectiveEnabled: effectiveEnabled,
          depth: depth + 1,
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
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sectionChildren,
    );
  }

  Component _buildValuesListChrome({
    required int length,
    required int cursor,
    required bool focused,
    required bool effectiveEnabled,
    required int depth,
  }) {
    final indent = '  ' * depth;
    final summary = length == 0
        ? '$indent(empty list)'
        : '$indent($length item${length == 1 ? '' : 's'}; cursor on [$cursor])';

    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: focused ? Colors.cyan : Colors.gray,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveEnabled ? summary : '$summary (read-only)',
            style: TextStyle(
              color: effectiveEnabled ? null : Colors.gray,
            ),
          ),
          Text(
            '$indent[a] add  [d] remove  ↑/↓ select  Shift+↑/↓ or k/j reorder',
            style: const TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
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
          variable is FoundryObjectVariable ||
          variable is FoundryValuesVariable ||
          _valuesAncestorPath(path) != null) {
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
      if (variable == null ||
          !_isChoiceVariable(variable) ||
          _valuesAncestorPath(path) != null) {
        continue;
      }
      // Only dirty choice values are raw input. Non-dirty cached values must
      // not pin defaults, or dependent defaultValue callbacks cannot recompute.
      if (!_dirtyKeys.contains(pathKey)) {
        continue;
      }
      _setAtPath(rawValues, path, choiceEntry.value);
    }

    _collectValuesLists(rawValues, parseErrors);

    return (
      rawValues: rawValues,
      parseErrors: parseErrors,
      topLevelDirtyKeys: _topLevelDirtyKeys(),
    );
  }

  void _collectValuesLists(
    Map<String, Object?> rawValues,
    Map<String, String> parseErrors,
  ) {
    for (final pathKey in _valuesLengths.keys.toList(growable: false)) {
      final path = _splitPath(pathKey);
      final variable = _variableAtPath(component.variableGroup, path);
      if (variable is! FoundryValuesVariable) {
        continue;
      }

      final length = _valuesLengths[pathKey]!;
      final isDirty = _isValuesPathUserTouched(pathKey);
      if (!isDirty && length > 0) {
        // Untouched defaulted lists stay out of raw input so defaults apply.
        continue;
      }
      if (!isDirty && length == 0) {
        // Empty editor with no default: contribute [] so submit yields a list.
        _setAtPath(rawValues, path, <Object?>[]);
        continue;
      }

      final list = <Object?>[
        for (var index = 0; index < length; index++)
          _collectValuesItemRaw(
            variable.item,
            [...path, '$index'],
            parseErrors,
          ),
      ];
      _setAtPath(rawValues, path, list);
    }
  }

  Object? _collectValuesItemRaw(
    FoundryVariable<dynamic> item,
    List<String> itemPath,
    Map<String, String> parseErrors,
  ) {
    if (item is FoundryObjectVariable) {
      final nested = <String, Object?>{};
      _collectNestedObjectRaw(
        group: item.group,
        pathPrefix: itemPath,
        into: nested,
        parseErrors: parseErrors,
      );
      return nested;
    }

    if (item is FoundryValuesVariable) {
      final pathKey = _joinPath(itemPath);
      final length = _valuesLengths[pathKey] ?? 0;
      return [
        for (var index = 0; index < length; index++)
          _collectValuesItemRaw(
            item.item,
            [...itemPath, '$index'],
            parseErrors,
          ),
      ];
    }

    final pathKey = _joinPath(itemPath);
    if (_isChoiceVariable(item)) {
      return _choiceRawValues[pathKey];
    }

    final controller = _controllers[pathKey];
    if (controller == null) {
      // Item slots may not be synced yet on the same frame as add.
      return _placeholderValuesItemRaw(item);
    }
    switch (parseCastVariableText(item, controller.text)) {
      case CastVariableTextParseSuccess(:final value):
        return value ?? _placeholderValuesItemRaw(item);
      case CastVariableTextParseFailure(:final message):
        parseErrors[pathKey] = message;
        return _placeholderValuesItemRaw(item);
    }
  }

  Object? _placeholderValuesItemRaw(FoundryVariable<dynamic> item) {
    return switch (item) {
      FoundryStringVariable() => '',
      FoundryBooleanVariable() => false,
      FoundryIntVariable() => 0,
      FoundryDoubleVariable() => 0.0,
      FoundrySingleChoiceVariable(:final options) =>
        options.isEmpty ? null : options.first,
      FoundryMultipleChoiceVariable() => const <Object?>[],
      FoundryObjectVariable() => const <String, Object?>{},
      FoundryValuesVariable() => const <Object?>[],
    };
  }

  void _seedNewValuesItem(
    FoundryVariable<dynamic> item,
    String itemPathKey,
  ) {
    if (item is FoundryObjectVariable) {
      _dirtyKeys.add(itemPathKey);
      return;
    }
    if (item is FoundryValuesVariable) {
      _valuesLengths[itemPathKey] = 0;
      _valuesCursors[itemPathKey] = 0;
      _dirtyKeys.add(itemPathKey);
      return;
    }
    if (_isChoiceVariable(item)) {
      final options = _choiceOptions(item);
      _choiceRawValues[itemPathKey] = switch (item) {
        FoundryMultipleChoiceVariable() => <Object?>[],
        _ => options.isEmpty ? null : options.first,
      };
      _optionCursorByKey[itemPathKey] = 0;
      _dirtyKeys.add(itemPathKey);
      return;
    }

    _controllers
        .putIfAbsent(
          itemPathKey,
          TextEditingController.new,
        )
        .text = switch (item) {
      FoundryBooleanVariable() => 'false',
      FoundryIntVariable() => '0',
      FoundryDoubleVariable() => '0.0',
      _ => '',
    };
    _dirtyKeys.add(itemPathKey);
  }

  void _collectNestedObjectRaw({
    required FoundryVariableGroup group,
    required List<String> pathPrefix,
    required Map<String, Object?> into,
    required Map<String, String> parseErrors,
  }) {
    for (final entry in group.variables.entries) {
      final path = [...pathPrefix, entry.key];
      final pathKey = _joinPath(path);
      final variable = entry.value;

      if (variable is FoundryObjectVariable) {
        final nested = <String, Object?>{};
        _collectNestedObjectRaw(
          group: variable.group,
          pathPrefix: path,
          into: nested,
          parseErrors: parseErrors,
        );
        into[entry.key] = nested;
        continue;
      }

      if (variable is FoundryValuesVariable) {
        final length = _valuesLengths[pathKey] ?? 0;
        into[entry.key] = [
          for (var index = 0; index < length; index++)
            _collectValuesItemRaw(
              variable.item,
              [...path, '$index'],
              parseErrors,
            ),
        ];
        continue;
      }

      if (_isChoiceVariable(variable)) {
        if (_dirtyKeys.contains(pathKey) ||
            _choiceRawValues.containsKey(pathKey)) {
          into[entry.key] = _choiceRawValues[pathKey];
        }
        continue;
      }

      final controller = _controllers[pathKey];
      if (controller == null) {
        continue;
      }
      switch (parseCastVariableText(variable, controller.text)) {
        case CastVariableTextParseSuccess(:final value):
          into[entry.key] = value;
        case CastVariableTextParseFailure(:final message):
          into[entry.key] = null;
          parseErrors[pathKey] = message;
      }
    }
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

    if (variable is FoundryValuesVariable) {
      return _handleValuesKeyEvent(
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

  bool _handleValuesKeyEvent(
    KeyboardEvent event, {
    required _FocusTarget focusedTarget,
    required List<_FocusTarget> focusTargets,
    required FoundryVariableGroupEvaluation evaluation,
    required FoundryVariableGroupValidation validation,
    required Map<String, String> parseErrors,
  }) {
    final pathKey = focusedTarget.pathKey;

    if (event.logicalKey == LogicalKey.enter) {
      if (_focusedIndex < focusTargets.length - 1) {
        setState(() => _focusedIndex = _focusedIndex + 1);
        return true;
      }
      _attemptSubmit(evaluation, validation, parseErrors);
      return true;
    }

    if (!focusedTarget.isEnabled) {
      return false;
    }

    if (event.logicalKey == LogicalKey.keyA) {
      setState(() {
        _dirtyKeys.add(pathKey);
        final length = _valuesLengths[pathKey] ?? 0;
        final valuesVariable =
            focusedTarget.entry.variable as FoundryValuesVariable;
        _seedNewValuesItem(
          valuesVariable.item,
          '$pathKey$_pathSeparator$length',
        );
        _valuesLengths[pathKey] = length + 1;
        _valuesCursors[pathKey] = length;
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.keyD ||
        event.logicalKey == LogicalKey.delete) {
      final length = _valuesLengths[pathKey] ?? 0;
      if (length == 0) {
        return true;
      }
      setState(() {
        _dirtyKeys.add(pathKey);
        final cursor = (_valuesCursors[pathKey] ?? 0).clamp(0, length - 1);
        _removeValuesItem(pathKey, cursor);
      });
      return true;
    }

    // Reorder: Shift/Ctrl+arrows, or k/j (Ctrl+arrows are often captured by the
    // OS / terminal, especially macOS Mission Control).
    if (_isValuesReorderUp(event)) {
      return _reorderValuesItem(pathKey, delta: -1);
    }
    if (_isValuesReorderDown(event)) {
      return _reorderValuesItem(pathKey, delta: 1);
    }

    if (event.logicalKey == LogicalKey.arrowUp) {
      final length = _valuesLengths[pathKey] ?? 0;
      if (length == 0) {
        return true;
      }
      setState(() {
        final cursor = _valuesCursors[pathKey] ?? 0;
        _valuesCursors[pathKey] = (cursor - 1 + length) % length;
      });
      return true;
    }

    if (event.logicalKey == LogicalKey.arrowDown) {
      final length = _valuesLengths[pathKey] ?? 0;
      if (length == 0) {
        return true;
      }
      setState(() {
        final cursor = _valuesCursors[pathKey] ?? 0;
        _valuesCursors[pathKey] = (cursor + 1) % length;
      });
      return true;
    }

    return false;
  }

  bool _isValuesReorderUp(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyK) {
      return true;
    }
    return event.logicalKey == LogicalKey.arrowUp &&
        (event.isShiftPressed || event.isControlPressed);
  }

  bool _isValuesReorderDown(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyJ) {
      return true;
    }
    return event.logicalKey == LogicalKey.arrowDown &&
        (event.isShiftPressed || event.isControlPressed);
  }

  bool _reorderValuesItem(String pathKey, {required int delta}) {
    final length = _valuesLengths[pathKey] ?? 0;
    if (length == 0) {
      return true;
    }
    setState(() {
      _dirtyKeys.add(pathKey);
      final cursor = (_valuesCursors[pathKey] ?? 0).clamp(0, length - 1);
      final target = cursor + delta;
      if (target < 0 || target >= length) {
        return;
      }
      _swapValuesItems(pathKey, cursor, target);
      _valuesCursors[pathKey] = target;
    });
    return true;
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

  /// Builds the interactive control for a non-section leaf field.
  ///
  /// Object and values variables are rendered as sections in
  /// [_buildGroupFields] and never reach this helper.
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

      if (entry.variable is FoundryValuesVariable) {
        final valuesVariable = entry.variable as FoundryValuesVariable;
        final length = _valuesLengths[pathKey] ?? 0;
        final resolvedList =
            entry.value is List ? entry.value! as List : const <Object?>[];

        targets.add(
          _FocusTarget(
            pathKey: pathKey,
            entry: entry,
            isEnabled: isEnabled,
          ),
        );

        for (var index = 0; index < length; index++) {
          final itemPath = [...path, '$index'];
          final itemVariable = valuesVariable.item;

          if (itemVariable is FoundryObjectVariable) {
            final nestedRaw = _valueAtPath(rawValues, itemPath);
            final nestedMap = _asStringKeyedMap(nestedRaw) ??
                _asStringKeyedMap(
                  index < resolvedList.length ? resolvedList[index] : null,
                ) ??
                const <String, Object?>{};
            final nestedEvaluation = itemVariable.group.evaluate(
              rawValues: nestedMap,
            );
            targets.addAll(
              _buildFocusTargets(
                evaluation: nestedEvaluation,
                rawValues: rawValues,
                pathPrefix: itemPath,
                ancestorsEnabled: isEnabled,
              ),
            );
            continue;
          }

          targets.add(
            _FocusTarget(
              pathKey: _joinPath(itemPath),
              entry: FoundryVariableEvaluationEntry(
                key: '$index',
                variable: itemVariable,
                value: index < resolvedList.length ? resolvedList[index] : null,
                isEnabled: isEnabled,
              ),
              isEnabled: isEnabled,
            ),
          );
        }
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

      if (variable is FoundryValuesVariable) {
        _clearTextFieldState(pathKey);
        _clearChoiceFieldState(pathKey);
        continue;
      }

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

    final activeValuesKeys = {
      for (final target in focusTargets)
        if (target.entry.variable is FoundryValuesVariable) target.pathKey,
    };
    _valuesLengths.removeWhere((key, _) => !activeValuesKeys.contains(key));
    _valuesCursors.removeWhere((key, _) => !activeValuesKeys.contains(key));
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
      if (variable is FoundryObjectVariable ||
          variable is FoundryValuesVariable) {
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

    FoundryVariableGroup? currentGroup = group;
    FoundryVariable<dynamic>? currentVariable;

    for (var index = 0; index < path.length; index++) {
      final segment = path[index];

      if (currentGroup != null) {
        currentVariable = currentGroup.variables[segment];
        currentGroup = null;
        if (currentVariable == null) {
          return null;
        }
        if (index == path.length - 1) {
          return currentVariable;
        }
        if (currentVariable is FoundryObjectVariable) {
          currentGroup = currentVariable.group;
          continue;
        }
        if (currentVariable is FoundryValuesVariable) {
          continue;
        }
        return null;
      }

      if (currentVariable is FoundryValuesVariable) {
        final itemIndex = int.tryParse(segment);
        if (itemIndex == null || itemIndex < 0) {
          return null;
        }
        currentVariable = currentVariable.item;
        if (index == path.length - 1) {
          return currentVariable;
        }
        if (currentVariable is FoundryObjectVariable) {
          currentGroup = currentVariable.group;
          continue;
        }
        if (currentVariable is FoundryValuesVariable) {
          continue;
        }
        return null;
      }

      return null;
    }

    return currentVariable;
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

  void _syncValuesListState(
    FoundryVariableGroupEvaluation evaluation, {
    required List<String> pathPrefix,
    required Map<String, Object?> rawValues,
  }) {
    for (final entry in evaluation.entries) {
      final path = [...pathPrefix, entry.key];
      final pathKey = _joinPath(path);

      if (entry.variable is FoundryValuesVariable) {
        final valuesVariable = entry.variable as FoundryValuesVariable;
        final userTouched = _isValuesPathUserTouched(pathKey);
        if (!userTouched) {
          _valuesLengths[pathKey] =
              entry.value is List ? (entry.value! as List).length : 0;
        }
        final length = _valuesLengths[pathKey] ?? 0;
        _valuesCursors[pathKey] = length == 0
            ? 0
            : (_valuesCursors[pathKey] ?? 0).clamp(0, length - 1);

        if (valuesVariable.item is FoundryObjectVariable) {
          final objectItem = valuesVariable.item as FoundryObjectVariable;
          final resolvedList =
              entry.value is List ? entry.value! as List : const <Object?>[];
          for (var index = 0; index < length; index++) {
            final itemPath = [...path, '$index'];
            final nestedRaw = _valueAtPath(rawValues, itemPath);
            final nestedMap = _asStringKeyedMap(nestedRaw) ??
                _asStringKeyedMap(
                  index < resolvedList.length ? resolvedList[index] : null,
                ) ??
                const <String, Object?>{};
            final nestedEvaluation = objectItem.group.evaluate(
              rawValues: nestedMap,
            );
            _syncValuesListState(
              nestedEvaluation,
              pathPrefix: itemPath,
              rawValues: rawValues,
            );
          }
        }
        continue;
      }

      if (entry.variable is FoundryObjectVariable) {
        final objectVariable = entry.variable as FoundryObjectVariable;
        final nestedRaw = _nestedRawMap(rawValues, path) ??
            _asStringKeyedMap(entry.value) ??
            const <String, Object?>{};
        final nestedEvaluation = objectVariable.group.evaluate(
          rawValues: nestedRaw,
        );
        _syncValuesListState(
          nestedEvaluation,
          pathPrefix: path,
          rawValues: rawValues,
        );
      }
    }
  }

  bool _needsValuesRecollect(Map<String, Object?> rawValues) {
    for (final entry in _valuesLengths.entries) {
      final current = _valueAtPath(rawValues, _splitPath(entry.key));
      if (entry.value == 0 && current is! List) {
        return true;
      }
      if (_isValuesPathUserTouched(entry.key) && current is! List) {
        return true;
      }
    }
    return false;
  }

  bool _isValuesPathUserTouched(String pathKey) {
    return _dirtyKeys.contains(pathKey) ||
        _dirtyKeys.any(
          (key) => key.startsWith('$pathKey$_pathSeparator'),
        );
  }

  List<String>? _valuesAncestorPath(List<String> path) {
    for (var length = 1; length < path.length; length++) {
      final candidate = path.sublist(0, length);
      final variable = _variableAtPath(component.variableGroup, candidate);
      if (variable is FoundryValuesVariable) {
        return candidate;
      }
    }
    return null;
  }

  bool _isIndexedListError(String error) {
    return RegExp(r'^\[\d+\]: ').hasMatch(error);
  }

  Object? _valueAtPath(Map<String, Object?> rawValues, List<String> path) {
    Object? current = rawValues;
    for (final segment in path) {
      if (current is Map) {
        current = current[segment];
        continue;
      }
      if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          return null;
        }
        current = current[index];
        continue;
      }
      return null;
    }
    return current;
  }

  Map<String, Object?>? _asStringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  void _removeValuesItem(String valuesPathKey, int index) {
    final length = _valuesLengths[valuesPathKey]!;
    // Shift item content down in place. Nocterm TextFields keep their original
    // controller instances across rebuilds, so remapping controller identity
    // would leave the visible text stale (or pointing at a disposed
    // controller).
    for (var from = index; from < length - 1; from++) {
      _copyPathPrefixState(
        '$valuesPathKey$_pathSeparator${from + 1}',
        '$valuesPathKey$_pathSeparator$from',
      );
    }
    _clearPathPrefix('$valuesPathKey$_pathSeparator${length - 1}');
    final nextLength = length - 1;
    _valuesLengths[valuesPathKey] = nextLength;
    _valuesCursors[valuesPathKey] =
        nextLength == 0 ? 0 : index.clamp(0, nextLength - 1);
  }

  void _swapValuesItems(String valuesPathKey, int a, int b) {
    if (a == b) {
      return;
    }
    _swapPathPrefixState(
      '$valuesPathKey$_pathSeparator$a',
      '$valuesPathKey$_pathSeparator$b',
    );
  }

  /// Copies path-keyed form state from [fromPrefix] onto [toPrefix] in place.
  ///
  /// Controller *identities* at [toPrefix] are preserved; only their text is
  /// replaced so mounted [TextField]s keep showing the bound controller.
  void _copyPathPrefixState(String fromPrefix, String toPrefix) {
    final suffixes = _pathPrefixSuffixes(fromPrefix)
      ..addAll(_pathPrefixSuffixes(toPrefix));

    for (final suffix in suffixes) {
      final fromKey = '$fromPrefix$suffix';
      final toKey = '$toPrefix$suffix';

      final fromController = _controllers[fromKey];
      if (fromController != null) {
        final toController = _controllers.putIfAbsent(
          toKey,
          TextEditingController.new,
        );
        if (toController.text != fromController.text) {
          toController.text = fromController.text;
        }
        _dirtyKeys.add(toKey);
      } else if (_controllers.containsKey(toKey)) {
        _controllers[toKey]!.text = '';
        _dirtyKeys.add(toKey);
      }

      _copyMapEntry(_choiceRawValues, fromKey, toKey);
      _copyMapEntry(_optionCursorByKey, fromKey, toKey);
      _copyMapEntry(_valuesLengths, fromKey, toKey);
      _copyMapEntry(_valuesCursors, fromKey, toKey);

      if (_dirtyKeys.contains(fromKey)) {
        _dirtyKeys.add(toKey);
      } else {
        _dirtyKeys.remove(toKey);
      }
    }
  }

  /// Swaps path-keyed form state between [prefixA] and [prefixB] in place.
  void _swapPathPrefixState(String prefixA, String prefixB) {
    final suffixes = _pathPrefixSuffixes(prefixA)
      ..addAll(_pathPrefixSuffixes(prefixB));

    for (final suffix in suffixes) {
      final keyA = '$prefixA$suffix';
      final keyB = '$prefixB$suffix';

      final controllerA = _controllers[keyA];
      final controllerB = _controllers[keyB];
      if (controllerA != null || controllerB != null) {
        final a = _controllers.putIfAbsent(keyA, TextEditingController.new);
        final b = _controllers.putIfAbsent(keyB, TextEditingController.new);
        final textA = a.text;
        a.text = b.text;
        b.text = textA;
        _dirtyKeys
          ..add(keyA)
          ..add(keyB);
      }

      _swapMapEntry(_choiceRawValues, keyA, keyB);
      _swapMapEntry(_optionCursorByKey, keyA, keyB);
      _swapMapEntry(_valuesLengths, keyA, keyB);
      _swapMapEntry(_valuesCursors, keyA, keyB);

      final dirtyA = _dirtyKeys.contains(keyA);
      final dirtyB = _dirtyKeys.contains(keyB);
      if (dirtyA != dirtyB) {
        if (dirtyA) {
          _dirtyKeys
            ..remove(keyA)
            ..add(keyB);
        } else {
          _dirtyKeys
            ..remove(keyB)
            ..add(keyA);
        }
      }
    }
  }

  Set<String> _pathPrefixSuffixes(String prefix) {
    final suffixes = <String>{};
    void consider(String key) {
      if (key == prefix || key.startsWith('$prefix$_pathSeparator')) {
        suffixes.add(key.substring(prefix.length));
      }
    }

    _controllers.keys.forEach(consider);
    _choiceRawValues.keys.forEach(consider);
    _optionCursorByKey.keys.forEach(consider);
    _valuesLengths.keys.forEach(consider);
    _valuesCursors.keys.forEach(consider);
    _dirtyKeys.forEach(consider);
    return suffixes;
  }

  void _copyMapEntry<V>(Map<String, V> map, String fromKey, String toKey) {
    if (map.containsKey(fromKey)) {
      map[toKey] = map[fromKey] as V;
    } else {
      map.remove(toKey);
    }
  }

  void _swapMapEntry<V>(Map<String, V> map, String keyA, String keyB) {
    final hasA = map.containsKey(keyA);
    final hasB = map.containsKey(keyB);
    if (!hasA && !hasB) {
      return;
    }
    final valueA = map[keyA];
    final valueB = map[keyB];
    if (hasB) {
      map[keyA] = valueB as V;
    } else {
      map.remove(keyA);
    }
    if (hasA) {
      map[keyB] = valueA as V;
    } else {
      map.remove(keyB);
    }
  }

  void _clearPathPrefix(String prefix) {
    final controllerKeys = _controllers.keys
        .where(
          (key) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
        )
        .toList(growable: false);
    for (final key in controllerKeys) {
      _controllers.remove(key)?.dispose();
    }
    _choiceRawValues.removeWhere(
      (key, _) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
    );
    _optionCursorByKey.removeWhere(
      (key, _) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
    );
    _dirtyKeys.removeWhere(
      (key) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
    );
    _valuesLengths.removeWhere(
      (key, _) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
    );
    _valuesCursors.removeWhere(
      (key, _) => key == prefix || key.startsWith('$prefix$_pathSeparator'),
    );
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
