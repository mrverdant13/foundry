import 'package:foundry_core/foundry_core.dart';

/// Copyable metadata for one mold variable, taken from a **live**
/// [FoundryVariableGroup] (callbacks like `displayLabel` still run).
///
/// Nested [FoundryObjectVariable] fields and [FoundryValuesVariable] item
/// schemas are included so inspect can report the same shape cast will see.
final class MoldVariableDescription {
  /// Creates a variable description entry.
  const MoldVariableDescription({
    required this.key,
    required this.kind,
    required this.label,
    this.description,
    this.placeholder,
    this.help,
    this.options = const [],
    this.fields = const [],
    this.item,
  });

  /// Decodes a [MoldVariableDescription] from a session result JSON map.
  factory MoldVariableDescription.fromJson(Map<String, Object?> json) {
    final key = json['key'];
    final kind = json['kind'];
    final label = json['label'];
    if (key is! String || kind is! String || label is! String) {
      throw const FormatException(
        'Variable description is missing key, kind, or label.',
      );
    }

    final options = <MoldVariableOptionDescription>[];
    final rawOptions = json['options'];
    if (rawOptions is List) {
      for (final entry in rawOptions) {
        if (entry is Map) {
          options.add(
            MoldVariableOptionDescription.fromJson({
              for (final mapEntry in entry.entries)
                if (mapEntry.key is String)
                  mapEntry.key as String: mapEntry.value,
            }),
          );
        }
      }
    }

    final fields = <MoldVariableDescription>[];
    final rawFields = json['fields'];
    if (rawFields is List) {
      for (final entry in rawFields) {
        if (entry is Map) {
          fields.add(
            MoldVariableDescription.fromJson({
              for (final mapEntry in entry.entries)
                if (mapEntry.key is String)
                  mapEntry.key as String: mapEntry.value,
            }),
          );
        }
      }
    }

    MoldVariableDescription? item;
    final rawItem = json['item'];
    if (rawItem is Map) {
      item = MoldVariableDescription.fromJson({
        for (final mapEntry in rawItem.entries)
          if (mapEntry.key is String) mapEntry.key as String: mapEntry.value,
      });
    }

    final description = json['description'];
    final placeholder = json['placeholder'];
    final help = json['help'];

    return MoldVariableDescription(
      key: key,
      kind: kind,
      label: label,
      description: description is String ? description : null,
      placeholder: placeholder is String ? placeholder : null,
      help: help is String ? help : null,
      options: options,
      fields: fields,
      item: item,
    );
  }

  /// Variable key in its enclosing [FoundryVariableGroup].
  final String key;

  /// Kind string matching the mold variables payload vocabulary
  /// (`string`, `boolean`, `int`, `double`, `single-choice`,
  /// `multiple-choice`, `object`, `values`).
  final String kind;

  /// Human-readable label from the live variable declaration.
  final String label;

  /// Longer TUI help text, when declared.
  final String? description;

  /// Ghost text for empty inputs, when declared.
  final String? placeholder;

  /// Short TUI footer hint, when declared.
  final String? help;

  /// Choice options with live `displayLabel` results (choice kinds only).
  final List<MoldVariableOptionDescription> options;

  /// Nested object fields ([FoundryObjectVariable] only).
  final List<MoldVariableDescription> fields;

  /// Element schema for a values list ([FoundryValuesVariable] only).
  final MoldVariableDescription? item;

  /// JSON-encodable map for the synthetic session result payload.
  Map<String, Object?> toJson() => {
        'key': key,
        'kind': kind,
        'label': label,
        if (description != null) 'description': description,
        if (placeholder != null) 'placeholder': placeholder,
        if (help != null) 'help': help,
        if (options.isNotEmpty)
          'options': [
            for (final option in options) option.toJson(),
          ],
        if (fields.isNotEmpty)
          'fields': [
            for (final field in fields) field.toJson(),
          ],
        if (item != null) 'item': item!.toJson(),
      };
}

/// One choice option with its live display label.
final class MoldVariableOptionDescription {
  /// Creates a choice option description.
  const MoldVariableOptionDescription({
    required this.value,
    required this.label,
  });

  /// Decodes a [MoldVariableOptionDescription] from JSON.
  factory MoldVariableOptionDescription.fromJson(Map<String, Object?> json) {
    final label = json['label'];
    if (label is! String) {
      throw const FormatException(
        'Variable option description is missing label.',
      );
    }
    return MoldVariableOptionDescription(
      value: json['value'],
      label: label,
    );
  }

  /// JSON-encodable option value (stringified when not JSON-safe).
  final Object? value;

  /// Label produced by the live `displayLabel` callback.
  final String label;

  /// JSON-encodable map for the synthetic session result payload.
  Map<String, Object?> toJson() => {
        'value': value,
        'label': label,
      };
}

/// Describes every variable in [variableGroup] using live declarations.
///
/// Walks the declaration map (including nested object fields and values-item
/// schemas). Does not evaluate visibility, defaults, or validators.
List<MoldVariableDescription> describeMoldVariableGroup(
  FoundryVariableGroup variableGroup,
) {
  return [
    for (final entry in variableGroup.variables.entries)
      _describeVariable(key: entry.key, variable: entry.value),
  ];
}

MoldVariableDescription _describeVariable({
  required String key,
  required FoundryVariable<dynamic> variable,
}) {
  return switch (variable) {
    FoundryStringVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'string',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
      ),
    FoundryBooleanVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'boolean',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
      ),
    FoundryIntVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'int',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
      ),
    FoundryDoubleVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'double',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
      ),
    FoundrySingleChoiceVariable() => _describeChoiceVariable(
        key: key,
        kind: 'single-choice',
        variable: variable,
      ),
    FoundryMultipleChoiceVariable() => _describeChoiceVariable(
        key: key,
        kind: 'multiple-choice',
        variable: variable,
      ),
    FoundryObjectVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
      :final group,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'object',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
        fields: describeMoldVariableGroup(group),
      ),
    FoundryValuesVariable(
      :final label,
      :final description,
      :final placeholder,
      :final help,
      :final item,
    ) =>
      MoldVariableDescription(
        key: key,
        kind: 'values',
        label: label,
        description: description,
        placeholder: placeholder,
        help: help,
        item: _describeVariable(key: 'item', variable: item),
      ),
  };
}

MoldVariableDescription _describeChoiceVariable({
  required String key,
  required String kind,
  required FoundryVariable<dynamic> variable,
}) {
  // Read options/displayLabel via `dynamic` so a concrete
  // `FoundrySingleChoiceVariable<String>` is not viewed as `<dynamic>`, which
  // would reject its `String Function(String)` callback at runtime.
  final dynamic choice = variable;
  // Ignore avoid_dynamic_calls: options/displayLabel must be read via dynamic.
  // ignore: avoid_dynamic_calls
  final options = List<Object?>.from(choice.options as List);
  // Ignore avoid_dynamic_calls: keep the concrete displayLabel function type.
  // ignore: avoid_dynamic_calls
  final displayLabel = choice.displayLabel as Function;

  return MoldVariableDescription(
    key: key,
    kind: kind,
    label: variable.label,
    description: variable.description,
    placeholder: variable.placeholder,
    help: variable.help,
    options: [
      for (final option in options)
        MoldVariableOptionDescription(
          value: _encodableOptionValue(option),
          label: Function.apply(displayLabel, [option]) as String,
        ),
    ],
  );
}

Object? _encodableOptionValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  return value.toString();
}
