import 'dart:convert';

import 'package:foundry_core/src/cast/cast_variable_inputs_result.dart';
import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:foundry_core/src/variables/foundry_variable_group.dart';

/// Parses and validates batch cast inputs (`--vars` / `--vars-file`).
///
/// [varsFileValues] is the decoded JSON object from `--vars-file` (or `null`
/// when the flag is omitted). [varsFlag] is the raw `--vars` string of
/// comma-separated `key=value` pairs (or `null`/empty when omitted).
///
/// Merge order: file values first, then `--vars` overrides colliding keys
/// (exact key strings). Dotted `--vars` keys (for example `publish.host`) are
/// expanded into nested object maps along `FoundryObjectVariable` groups and
/// deep-merged with nested JSON object values from `--vars-file`. Whole-object
/// `--vars` flag assignments (JSON strings) never merge with dotted children,
/// even if the JSON parses to an object; only `--vars-file` object values do.
/// Unknown keys fail. Per-kind parse/type failures list offending keys.
/// After a successful merge/parse, the group is evaluated and validated with
/// the same visibility and validator rules as interactive cast.
///
/// [seedValues] are merged under the parsed user inputs for evaluation
/// (for example prepare-hook context). User-provided keys win on collision.
/// A non-null seed for a declared variable key is treated as that variable's
/// raw value when the user did not supply one (it resolves directly, not only
/// as callback context). Keys that are not variable names remain visible to
/// `defaultValue` / `visibleWhen` callbacks. Seed entries are not returned in
/// [CastVariableInputsParseSuccess.rawValues].
///
/// This API is pure (no I/O, no Nocterm). The CLI is responsible for reading
/// the vars file from disk and decoding JSON before calling this function.
CastVariableInputsParseResult parseCastVariableInputs({
  required FoundryVariableGroup variableGroup,
  Map<String, Object?>? varsFileValues,
  String? varsFlag,
  Map<String, Object?> seedValues = const {},
}) {
  final flagParse = _parseVarsFlag(varsFlag);
  if (flagParse.error != null) {
    return CastVariableInputsParseFailure(varsFlagError: flagParse.error);
  }

  final flatMerged = <String, _RawInput>{
    if (varsFileValues != null)
      for (final entry in varsFileValues.entries)
        entry.key: _RawInput.json(entry.value),
    for (final entry in flagParse.pairs) entry.key: _RawInput.flag(entry.value),
  };

  final expansion = _expandDottedInputs(
    flatMerged: flatMerged,
    variableGroup: variableGroup,
  );
  if (expansion.failure != null) {
    return expansion.failure!;
  }

  final unknownKeys = <String>[];
  final parseErrors = <String, String>{};
  final rawValues = <String, Object?>{};

  for (final entry in expansion.values.entries) {
    final key = entry.key;
    final variable = variableGroup.variables[key];
    if (variable == null) {
      unknownKeys.add(key);
      continue;
    }

    final parsed = _parseMergedValue(
      variable: variable,
      value: entry.value,
      keyPath: key,
    );
    switch (parsed) {
      case _ParsedValue(:final value):
        rawValues[key] = value;
      case _ParsedFailure(:final message):
        parseErrors[key] = message;
      case _ParsedNestedFailure(
          unknown: final nestedUnknown,
          errors: final nestedErrors,
        ):
        unknownKeys.addAll(nestedUnknown);
        parseErrors.addAll(nestedErrors);
    }
  }

  if (unknownKeys.isNotEmpty || parseErrors.isNotEmpty) {
    unknownKeys.sort();
    return CastVariableInputsParseFailure(
      unknownKeys: List.unmodifiable(unknownKeys),
      parseErrors: Map.unmodifiable(parseErrors),
    );
  }

  final evaluation = variableGroup.evaluate(
    rawValues: {...seedValues, ...rawValues},
    dirtyKeys: rawValues.keys.toSet(),
  );
  final validation = variableGroup.validate(evaluation);
  if (!validation.isValid) {
    return CastVariableInputsParseFailure(validation: validation);
  }

  return CastVariableInputsParseSuccess(
    rawValues: Map.unmodifiable(rawValues),
    evaluation: evaluation,
  );
}

/// Intermediate tree after expanding dotted `--vars` keys.
sealed class _MergedValue {
  const _MergedValue();
}

final class _MergedLeaf extends _MergedValue {
  const _MergedLeaf(this.input);
  final _RawInput input;
}

final class _MergedObject extends _MergedValue {
  _MergedObject([Map<String, _MergedValue>? fields])
      : fields = fields ?? <String, _MergedValue>{};

  final Map<String, _MergedValue> fields;
}

final class _ExpandDottedResult {
  const _ExpandDottedResult({
    this.values = const {},
    this.failure,
  });

  final Map<String, _MergedValue> values;
  final CastVariableInputsParseFailure? failure;
}

/// Expands flat `key` / `a.b.c` inputs into a nested [_MergedValue] tree.
///
/// Nested JSON maps from `--vars-file` become [_MergedObject] trees so dotted
/// `--vars` leaves can deep-merge into them. A `--vars` flag assignment at the
/// same path never deep-merges — even when its JSON string decodes to a map —
/// and conflicts with any dotted children for that path. A `--vars-file` value
/// that is not a map likewise conflicts with dotted children.
_ExpandDottedResult _expandDottedInputs({
  required Map<String, _RawInput> flatMerged,
  required FoundryVariableGroup variableGroup,
}) {
  final values = <String, _MergedValue>{};
  final parseErrors = <String, String>{};
  final unknownKeys = <String>[];

  final plainKeys = <String>[];
  final dottedKeys = <String>[];
  for (final key in flatMerged.keys) {
    if (key.contains('.')) {
      dottedKeys.add(key);
    } else {
      plainKeys.add(key);
    }
  }

  // A flag whole-object assignment at `publish` (JSON object string) conflicts
  // with `publish.*`. Nested JSON maps from `--vars-file` deep-merge with
  // dotted flag leaves instead.
  for (final dottedKey in dottedKeys) {
    final segments = dottedKey.split('.');
    if (segments.any((segment) => segment.isEmpty)) {
      continue;
    }
    for (var index = 1; index < segments.length; index++) {
      final prefix = segments.sublist(0, index).join('.');
      final prefixInput = flatMerged[prefix];
      if (prefixInput == null) {
        continue;
      }
      final canDeepMerge = switch (prefixInput) {
        _JsonRawInput(:final value) => value is Map,
        _FlagRawInput() => false,
      };
      if (!canDeepMerge) {
        parseErrors[dottedKey] =
            'Conflicts with a whole-object assignment at "$prefix"; remove '
            'the object value or the dotted children.';
        break;
      }
    }
  }
  if (parseErrors.isNotEmpty) {
    return _ExpandDottedResult(
      failure: CastVariableInputsParseFailure(
        parseErrors: Map.unmodifiable(parseErrors),
      ),
    );
  }

  for (final key in plainKeys) {
    final input = flatMerged[key]!;
    final variable = variableGroup.variables[key];
    final converted = _mergedValueFromRaw(
      input: input,
      variable: variable,
      keyPath: key,
    );
    switch (converted) {
      case _MergedFromRawSuccess(:final value):
        values[key] = value;
      case _MergedFromRawFailure(:final message):
        parseErrors[key] = message;
    }
  }

  for (final key in dottedKeys) {
    final segments = key.split('.');
    if (segments.any((segment) => segment.isEmpty)) {
      parseErrors[key] = 'Invalid dotted path; empty segments are not allowed.';
      continue;
    }

    final conflict = _assignDottedPath(
      root: values,
      segments: segments,
      input: flatMerged[key]!,
      variableGroup: variableGroup,
      fullPath: key,
    );
    if (conflict != null) {
      if (conflict.unknown) {
        unknownKeys.add(conflict.message);
      } else {
        parseErrors[key] = conflict.message;
      }
    }
  }

  if (unknownKeys.isNotEmpty || parseErrors.isNotEmpty) {
    unknownKeys.sort();
    return _ExpandDottedResult(
      failure: CastVariableInputsParseFailure(
        unknownKeys: List.unmodifiable(unknownKeys),
        parseErrors: Map.unmodifiable(parseErrors),
      ),
    );
  }

  return _ExpandDottedResult(values: values);
}

final class _DottedAssignError {
  const _DottedAssignError(this.message, {this.unknown = false});
  final String message;
  final bool unknown;
}

sealed class _MergedFromRawResult {
  const _MergedFromRawResult();
}

final class _MergedFromRawSuccess extends _MergedFromRawResult {
  const _MergedFromRawSuccess(this.value);
  final _MergedValue value;
}

final class _MergedFromRawFailure extends _MergedFromRawResult {
  const _MergedFromRawFailure(this.message);
  final String message;
}

_MergedFromRawResult _mergedValueFromRaw({
  required _RawInput input,
  required FoundryVariable<dynamic>? variable,
  required String keyPath,
}) {
  if (variable is! FoundryObjectVariable) {
    return _MergedFromRawSuccess(_MergedLeaf(input));
  }

  switch (input) {
    case _JsonRawInput(:final value):
      if (value == null) {
        return const _MergedFromRawSuccess(_MergedLeaf(_RawInput.json(null)));
      }
      if (value is! Map) {
        return _MergedFromRawSuccess(_MergedLeaf(input));
      }
      return _mergedObjectFromJsonMap(
        map: value,
        group: variable.group,
        keyPath: keyPath,
      );
    case _FlagRawInput(:final value):
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const _MergedFromRawSuccess(_MergedLeaf(_RawInput.flag('')));
      }
      if (!trimmed.startsWith('{')) {
        return _MergedFromRawSuccess(_MergedLeaf(input));
      }
      late final Object decoded;
      try {
        decoded = jsonDecode(trimmed) as Object;
      } on FormatException {
        return const _MergedFromRawFailure('Invalid JSON object.');
      }
      if (decoded is! Map) {
        return const _MergedFromRawFailure('Expected a JSON object.');
      }
      return _mergedObjectFromJsonMap(
        map: decoded,
        group: variable.group,
        keyPath: keyPath,
      );
  }
}

_MergedFromRawResult _mergedObjectFromJsonMap({
  required Map<dynamic, dynamic> map,
  required FoundryVariableGroup group,
  required String keyPath,
}) {
  final fields = <String, _MergedValue>{};
  for (final entry in map.entries) {
    final childKey = entry.key.toString();
    final childPath = '$keyPath.$childKey';
    final childVariable = group.variables[childKey];
    final child = _mergedValueFromRaw(
      input: _RawInput.json(entry.value),
      variable: childVariable,
      keyPath: childPath,
    );
    switch (child) {
      case _MergedFromRawSuccess(:final value):
        fields[childKey] = value;
      case _MergedFromRawFailure(:final message):
        return _MergedFromRawFailure(message);
    }
  }
  return _MergedFromRawSuccess(_MergedObject(fields));
}

_DottedAssignError? _assignDottedPath({
  required Map<String, _MergedValue> root,
  required List<String> segments,
  required _RawInput input,
  required FoundryVariableGroup variableGroup,
  required String fullPath,
}) {
  var group = variableGroup;
  var cursor = root;
  final pathParts = <String>[];

  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    pathParts.add(segment);
    final path = pathParts.join('.');
    final isLeaf = index == segments.length - 1;
    final variable = group.variables[segment];

    if (variable == null) {
      // Echo the full user-typed path when an intermediate segment fails.
      final unknownKey =
          path == fullPath ? path : '$path (in "$fullPath")';
      return _DottedAssignError(unknownKey, unknown: true);
    }

    if (isLeaf) {
      final existing = cursor[segment];
      if (existing is _MergedObject) {
        return const _DottedAssignError(
          'Conflicts with an object value at this path; use nested fields or '
          'a single object assignment, not both.',
        );
      }
      cursor[segment] = _MergedLeaf(input);
      return null;
    }

    if (variable is! FoundryObjectVariable) {
      return _DottedAssignError(
        'Cannot use dotted path "$fullPath"; '
        '"$path" is not an object variable.',
      );
    }

    final existing = cursor[segment];
    if (existing == null) {
      final objectNode = _MergedObject();
      cursor[segment] = objectNode;
      cursor = objectNode.fields;
      group = variable.group;
      continue;
    }
    if (existing is _MergedLeaf) {
      return _DottedAssignError(
        'Conflicts with a whole-object assignment at "$path"; remove the '
        'object value or the dotted children.',
      );
    }
    cursor = (existing as _MergedObject).fields;
    group = variable.group;
  }

  return null;
}

_ParsedInput _parseMergedValue({
  required FoundryVariable<dynamic> variable,
  required _MergedValue value,
  required String keyPath,
}) {
  return switch (value) {
    _MergedLeaf(:final input) => _parseInputForVariable(
        variable: variable,
        input: input,
        keyPath: keyPath,
      ),
    _MergedObject(:final fields) => variable is FoundryObjectVariable
        ? _parseObjectMerged(
            variable: variable,
            fields: fields,
            keyPath: keyPath,
          )
        : const _ParsedFailure(
            'Expected a scalar value but found a nested object path.',
          ),
  };
}

_ParsedInput _parseObjectMerged({
  required FoundryObjectVariable variable,
  required Map<String, _MergedValue> fields,
  required String keyPath,
}) {
  final unknown = <String>[];
  final errors = <String, String>{};
  final parsedMap = <String, Object?>{};

  for (final entry in fields.entries) {
    final childKey = entry.key;
    final childPath = '$keyPath.$childKey';
    final childVariable = variable.group.variables[childKey];
    if (childVariable == null) {
      unknown.add(childPath);
      continue;
    }

    final parsed = _parseMergedValue(
      variable: childVariable,
      value: entry.value,
      keyPath: childPath,
    );
    switch (parsed) {
      case _ParsedValue(:final value):
        parsedMap[childKey] = value;
      case _ParsedFailure(:final message):
        errors[childPath] = message;
      case _ParsedNestedFailure(
          unknown: final nestedUnknown,
          errors: final nestedErrors,
        ):
        unknown.addAll(nestedUnknown);
        errors.addAll(nestedErrors);
    }
  }

  if (unknown.isNotEmpty || errors.isNotEmpty) {
    return _ParsedNestedFailure(unknown: unknown, errors: errors);
  }
  return _ParsedValue(parsedMap);
}

final class _VarsFlagParse {
  const _VarsFlagParse({
    this.pairs = const [],
    this.error,
  });

  final List<MapEntry<String, String>> pairs;
  final String? error;
}

/// Splits a `--vars` string into `key=value` pairs.
///
/// Pairs are separated by commas (optional whitespace after each comma is
/// allowed). Values may themselves contain commas (for example multi-choice or
/// values-list tokens); the next pair starts at `, key=` where `key` contains
/// no `=` or `,` and does not begin with whitespace.
_VarsFlagParse _parseVarsFlag(String? varsFlag) {
  if (varsFlag == null) {
    return const _VarsFlagParse();
  }
  final input = varsFlag.trim();
  if (input.isEmpty) {
    return const _VarsFlagParse();
  }

  final keyPattern = RegExp(r'(?:^|,)\s*([^=,\s][^=,]*)=');
  final matches = keyPattern.allMatches(input).toList(growable: false);
  if (matches.isEmpty || matches.first.start != 0) {
    return const _VarsFlagParse(
      error: 'Invalid --vars format; expected comma-separated key=value pairs.',
    );
  }

  final pairs = <MapEntry<String, String>>[];
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final key = match.group(1)!;
    final valueStart = match.end;
    final valueEnd =
        index + 1 < matches.length ? matches[index + 1].start : input.length;
    pairs.add(MapEntry(key, input.substring(valueStart, valueEnd)));
  }

  return _VarsFlagParse(pairs: pairs);
}

sealed class _RawInput {
  const _RawInput();

  const factory _RawInput.json(Object? value) = _JsonRawInput;
  const factory _RawInput.flag(String value) = _FlagRawInput;
}

final class _JsonRawInput extends _RawInput {
  const _JsonRawInput(this.value);
  final Object? value;
}

final class _FlagRawInput extends _RawInput {
  const _FlagRawInput(this.value);
  final String value;
}

sealed class _ParsedInput {
  const _ParsedInput();
}

final class _ParsedValue extends _ParsedInput {
  const _ParsedValue(this.value);
  final Object? value;
}

final class _ParsedFailure extends _ParsedInput {
  const _ParsedFailure(this.message);
  final String message;
}

final class _ParsedNestedFailure extends _ParsedInput {
  const _ParsedNestedFailure({
    required this.unknown,
    required this.errors,
  });

  final List<String> unknown;
  final Map<String, String> errors;
}

_ParsedInput _parseInputForVariable({
  required FoundryVariable<dynamic> variable,
  required _RawInput input,
  required String keyPath,
}) {
  return switch (input) {
    _JsonRawInput(:final value) => _parseJsonValue(
        variable: variable,
        value: value,
        keyPath: keyPath,
      ),
    _FlagRawInput(:final value) => _parseFlagValue(
        variable: variable,
        text: value,
        keyPath: keyPath,
      ),
  };
}

_ParsedInput _parseJsonValue({
  required FoundryVariable<dynamic> variable,
  required Object? value,
  required String keyPath,
}) {
  if (value == null) {
    return const _ParsedValue(null);
  }

  return switch (variable) {
    FoundryStringVariable() => value is String
        ? _ParsedValue(value)
        : _ParsedFailure(
            'Expected a string but found ${value.runtimeType}.',
          ),
    FoundryBooleanVariable() => value is bool
        ? _ParsedValue(value)
        : _ParsedFailure(
            'Expected a boolean but found ${value.runtimeType}.',
          ),
    FoundryIntVariable() => _parseJsonInt(value),
    FoundryDoubleVariable() => value is num
        ? _ParsedValue(value.toDouble())
        : _ParsedFailure(
            'Expected a number but found ${value.runtimeType}.',
          ),
    FoundrySingleChoiceVariable() => _parseChoiceJson(
        variable: variable,
        value: value,
      ),
    FoundryMultipleChoiceVariable() => _parseMultiChoiceJson(
        variable: variable,
        value: value,
      ),
    FoundryObjectVariable() => _parseObjectJson(
        variable: variable,
        value: value,
        keyPath: keyPath,
      ),
    FoundryValuesVariable() => _parseValuesJson(
        variable: variable,
        value: value,
        keyPath: keyPath,
      ),
  };
}

_ParsedInput _parseJsonInt(Object value) {
  if (value is int) {
    return _ParsedValue(value);
  }
  if (value is double && value == value.truncateToDouble()) {
    return _ParsedValue(value.toInt());
  }
  return _ParsedFailure(
    'Expected an integer but found ${value.runtimeType}.',
  );
}

_ParsedInput _parseFlagValue({
  required FoundryVariable<dynamic> variable,
  required String text,
  required String keyPath,
}) {
  return switch (variable) {
    FoundryStringVariable() => _ParsedValue(text),
    FoundryBooleanVariable() => _parseBooleanFlag(text),
    FoundryIntVariable() => _parseIntFlag(text),
    FoundryDoubleVariable() => _parseDoubleFlag(text),
    FoundrySingleChoiceVariable() => _parseSingleChoiceFlag(
        variable: variable,
        text: text,
      ),
    FoundryMultipleChoiceVariable() => _parseMultipleChoiceFlag(
        variable: variable,
        text: text,
      ),
    FoundryObjectVariable() => _parseObjectFlag(
        variable: variable,
        text: text,
        keyPath: keyPath,
      ),
    FoundryValuesVariable() => _parseValuesFlag(
        variable: variable,
        text: text,
        keyPath: keyPath,
      ),
  };
}

_ParsedInput _parseBooleanFlag(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(null);
  }
  return switch (trimmed.toLowerCase()) {
    'true' || 'yes' || 'y' || '1' => const _ParsedValue(true),
    'false' || 'no' || 'n' || '0' => const _ParsedValue(false),
    _ => const _ParsedFailure('Enter yes/no or true/false'),
  };
}

_ParsedInput _parseIntFlag(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(null);
  }
  final value = int.tryParse(trimmed);
  if (value == null) {
    return const _ParsedFailure('Enter a valid integer');
  }
  return _ParsedValue(value);
}

_ParsedInput _parseDoubleFlag(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(null);
  }
  final value = double.tryParse(trimmed);
  if (value == null) {
    return const _ParsedFailure('Enter a valid number');
  }
  return _ParsedValue(value);
}

_ParsedInput _parseChoiceJson({
  required FoundrySingleChoiceVariable<dynamic> variable,
  required Object value,
}) {
  final matched = _matchChoiceOption(variable: variable, token: value);
  if (matched == null) {
    return const _ParsedFailure('Value is not a valid option.');
  }
  return _ParsedValue(matched);
}

_ParsedInput _parseMultiChoiceJson({
  required FoundryMultipleChoiceVariable<dynamic> variable,
  required Object value,
}) {
  if (value is! List) {
    return _ParsedFailure(
      'Expected a list of options but found ${value.runtimeType}.',
    );
  }

  final selected = <Object?>[];
  for (final element in value) {
    final matched = _matchChoiceOption(variable: variable, token: element);
    if (matched == null) {
      return const _ParsedFailure('Value is not a valid option.');
    }
    selected.add(matched);
  }
  return _ParsedValue(selected);
}

_ParsedInput _parseSingleChoiceFlag({
  required FoundrySingleChoiceVariable<dynamic> variable,
  required String text,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(null);
  }
  final matched = _matchChoiceOption(variable: variable, token: trimmed);
  if (matched == null) {
    return const _ParsedFailure('Value is not a valid option.');
  }
  return _ParsedValue(matched);
}

_ParsedInput _parseMultipleChoiceFlag({
  required FoundryMultipleChoiceVariable<dynamic> variable,
  required String text,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(<Object?>[]);
  }

  final tokens = trimmed
      .split(',')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty);
  final selected = <Object?>[];
  for (final token in tokens) {
    final matched = _matchChoiceOption(variable: variable, token: token);
    if (matched == null) {
      return const _ParsedFailure('Value is not a valid option.');
    }
    selected.add(matched);
  }
  return _ParsedValue(selected);
}

Object? _matchChoiceOption({
  required FoundryVariable<dynamic> variable,
  required Object? token,
}) {
  final options = _choiceOptions(variable);
  if (options == null) {
    return null;
  }

  for (final option in options) {
    if (option == token) {
      return option;
    }
  }

  if (token is! String) {
    return null;
  }

  for (final option in options) {
    if (option?.toString() == token) {
      return option;
    }
    if (_choiceDisplayLabel(variable, option) == token) {
      return option;
    }
  }

  for (final option in options) {
    if (option is int && int.tryParse(token) == option) {
      return option;
    }
    if (option is double && double.tryParse(token) == option) {
      return option;
    }
    if (option is bool) {
      final parsed = _parseBooleanFlag(token);
      if (parsed is _ParsedValue && parsed.value == option) {
        return option;
      }
    }
  }

  return null;
}

List<Object?>? _choiceOptions(FoundryVariable<dynamic> variable) {
  return switch (variable) {
    FoundrySingleChoiceVariable(:final options) => List<Object?>.of(options),
    FoundryMultipleChoiceVariable(:final options) => List<Object?>.of(options),
    _ => null,
  };
}

/// Reads `displayLabel` without promoting a choice variable to `…<dynamic>`
/// (the callback's parameter type is contravariant).
String _choiceDisplayLabel(
  FoundryVariable<dynamic> variable,
  Object? option,
) {
  return ((variable as dynamic).displayLabel as Function)(option) as String;
}

_ParsedInput _parseObjectJson({
  required FoundryObjectVariable variable,
  required Object value,
  required String keyPath,
}) {
  if (value is! Map) {
    return _ParsedFailure(
      'Expected an object but found ${value.runtimeType}.',
    );
  }

  final nestedRaw = <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
  return _parseObjectMap(
    group: variable.group,
    nestedRaw: nestedRaw,
    keyPath: keyPath,
  );
}

_ParsedInput _parseObjectFlag({
  required FoundryObjectVariable variable,
  required String text,
  required String keyPath,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(null);
  }
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return const _ParsedFailure(
      'Object values require --vars-file or a JSON object string.',
    );
  }

  final Object decoded;
  try {
    decoded = jsonDecode(trimmed) as Object;
  } on FormatException {
    return const _ParsedFailure('Invalid JSON object.');
  }
  if (decoded is! Map) {
    return const _ParsedFailure('Expected a JSON object.');
  }

  final nestedRaw = <String, Object?>{
    for (final entry in decoded.entries) entry.key.toString(): entry.value,
  };
  return _parseObjectMap(
    group: variable.group,
    nestedRaw: nestedRaw,
    keyPath: keyPath,
  );
}

_ParsedInput _parseObjectMap({
  required FoundryVariableGroup group,
  required Map<String, Object?> nestedRaw,
  required String keyPath,
}) {
  final unknown = <String>[];
  final errors = <String, String>{};
  final parsedMap = <String, Object?>{};

  for (final entry in nestedRaw.entries) {
    final childKey = entry.key;
    final childPath = '$keyPath.$childKey';
    final childVariable = group.variables[childKey];
    if (childVariable == null) {
      unknown.add(childPath);
      continue;
    }

    final parsed = _parseInputForVariable(
      variable: childVariable,
      input: _RawInput.json(entry.value),
      keyPath: childPath,
    );
    switch (parsed) {
      case _ParsedValue(:final value):
        parsedMap[childKey] = value;
      case _ParsedFailure(:final message):
        errors[childPath] = message;
      case _ParsedNestedFailure(
          unknown: final nestedUnknown,
          errors: final nestedErrors,
        ):
        unknown.addAll(nestedUnknown);
        errors.addAll(nestedErrors);
    }
  }

  if (unknown.isNotEmpty || errors.isNotEmpty) {
    return _ParsedNestedFailure(unknown: unknown, errors: errors);
  }
  return _ParsedValue(parsedMap);
}

_ParsedInput _parseValuesJson({
  required FoundryValuesVariable<dynamic> variable,
  required Object value,
  required String keyPath,
}) {
  if (value is! List) {
    return _ParsedFailure(
      'Expected a list but found ${value.runtimeType}.',
    );
  }

  final elements = <Object?>[];
  final errors = <String, String>{};
  for (var index = 0; index < value.length; index++) {
    final elementPath = '$keyPath[$index]';
    final parsed = _parseJsonValue(
      variable: variable.item,
      value: value[index],
      keyPath: elementPath,
    );
    switch (parsed) {
      case _ParsedValue(value: final parsedValue):
        elements.add(parsedValue);
      case _ParsedFailure(:final message):
        errors[elementPath] = message;
      case _ParsedNestedFailure(
          unknown: final nestedUnknown,
          errors: final nestedErrors,
        ):
        return _ParsedNestedFailure(
          unknown: nestedUnknown,
          errors: {...errors, ...nestedErrors},
        );
    }
  }

  if (errors.isNotEmpty) {
    return _ParsedNestedFailure(unknown: const [], errors: errors);
  }
  return _ParsedValue(elements);
}

_ParsedInput _parseValuesFlag({
  required FoundryValuesVariable<dynamic> variable,
  required String text,
  required String keyPath,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedValue(<Object?>[]);
  }

  if (trimmed.startsWith('[')) {
    late final Object decoded;
    try {
      decoded = jsonDecode(trimmed) as Object;
    } on FormatException {
      return const _ParsedFailure('Invalid JSON array.');
    }
    return _parseValuesJson(
      variable: variable,
      value: decoded,
      keyPath: keyPath,
    );
  }

  final tokens = trimmed.split(',').map((token) => token.trim());
  final elements = <Object?>[];
  final errors = <String, String>{};
  var index = 0;
  for (final token in tokens) {
    if (token.isEmpty) {
      continue;
    }
    final elementPath = '$keyPath[$index]';
    final parsed = _parseFlagValue(
      variable: variable.item,
      text: token,
      keyPath: elementPath,
    );
    switch (parsed) {
      case _ParsedValue(:final value):
        elements.add(value);
      case _ParsedFailure(:final message):
        errors[elementPath] = message;
      case _ParsedNestedFailure(
          unknown: final nestedUnknown,
          errors: final nestedErrors,
        ):
        return _ParsedNestedFailure(
          unknown: nestedUnknown,
          errors: {...errors, ...nestedErrors},
        );
    }
    index++;
  }

  if (errors.isNotEmpty) {
    return _ParsedNestedFailure(unknown: const [], errors: errors);
  }
  return _ParsedValue(elements);
}
