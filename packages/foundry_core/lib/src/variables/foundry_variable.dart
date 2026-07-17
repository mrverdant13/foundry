import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:meta/meta.dart';

/// Callback that decides whether a variable is visible for the current cast
/// values.
///
/// Receives a [SnapshotFoundryContext] — never a mutable `FoundryContext`.
typedef FoundryVisibleWhen = bool Function(SnapshotFoundryContext context);

/// Callback that decides whether a visible variable is editable for the
/// current cast values.
///
/// When it evaluates to `false`, the variable stays visible but is shown
/// read-only. Receives a [SnapshotFoundryContext] — never a mutable
/// `FoundryContext`.
typedef FoundryEnabledWhen = bool Function(SnapshotFoundryContext context);

/// Callback that derives a variable's default value from the current cast
/// values.
///
/// Receives a [SnapshotFoundryContext] — never a mutable `FoundryContext`.
typedef FoundryDefaultValue<T> = T Function(SnapshotFoundryContext context);

/// Per-variable validation callback.
///
/// Returns a human-readable error message, or `null` when [value] is valid.
/// Receives a [SnapshotFoundryContext] — never a mutable `FoundryContext`.
typedef FoundryFieldValidator<T> = String? Function(
  T? value,
  SnapshotFoundryContext context,
);

/// Cross-field validation callback for a whole `FoundryVariableGroup`.
///
/// Returns a human-readable error message, or `null` when the group is
/// valid. Receives a [SnapshotFoundryContext] — never a mutable
/// `FoundryContext`.
typedef FoundryGroupValidator = String? Function(
  SnapshotFoundryContext context,
);

/// Maps a choice option to the label shown in the variable TUI.
typedef FoundryDisplayLabel<T> = String Function(T value);

/// Base type for variables declared in a mold's `variables.dart`.
///
/// Concrete kinds include [FoundryStringVariable], [FoundryBooleanVariable],
/// [FoundryIntVariable], [FoundryDoubleVariable],
/// [FoundrySingleChoiceVariable], and [FoundryMultipleChoiceVariable];
/// additional kinds are added as the runtime expands.
@immutable
sealed class FoundryVariable<T> {
  /// Creates a [FoundryVariable].
  const FoundryVariable({
    required this.label,
    this.visibleWhen,
    this.enabledWhen,
    this.defaultValue,
    this.validators = const [],
    this.description,
    this.placeholder,
    this.help,
  });

  /// Human-readable label shown in the variable TUI.
  final String label;

  /// Callback deciding whether this variable is visible; `null` means
  /// always visible.
  final FoundryVisibleWhen? visibleWhen;

  /// Callback deciding whether this variable is editable; `null` means
  /// always enabled. When it evaluates to `false`, the variable remains
  /// visible but is shown read-only.
  final FoundryEnabledWhen? enabledWhen;

  /// Callback deriving this variable's default value when the user has not
  /// supplied one; `null` means no computed default.
  final FoundryDefaultValue<T>? defaultValue;

  /// Per-variable validation callbacks, run in order.
  final List<FoundryFieldValidator<T>> validators;

  /// Longer help text shown alongside the field in the TUI.
  final String? description;

  /// Ghost text shown in an empty text input.
  final String? placeholder;

  /// Short hint or footer copy shown in the TUI.
  final String? help;

  /// Whether this variable is visible given the current [context].
  ///
  /// Variables with no [visibleWhen] callback are always visible.
  bool isVisible(SnapshotFoundryContext context) =>
      visibleWhen?.call(context) ?? true;

  /// Whether this variable is editable given the current [context].
  ///
  /// Variables with no [enabledWhen] callback are always enabled.
  bool isEnabled(SnapshotFoundryContext context) =>
      enabledWhen?.call(context) ?? true;

  /// Resolves this variable's value for the current evaluation pass.
  ///
  /// A manually supplied value is preserved when [key] is present and
  /// non-null in [rawValues], or when [key] is in [dirtyKeys] (the user has
  /// edited it, even if it was cleared back to a falsy value some kinds may
  /// treat as "unset"). Otherwise, [defaultValue] is derived against a
  /// [SnapshotFoundryContext] built from [resolvedValues] merged with
  /// [rawValues].
  ///
  /// Throws [FoundryContextException] if the raw value for [key] is
  /// non-null and not a [T], so a mistyped input is reported here rather
  /// than surfacing later as an opaque cast failure.
  Object? resolveValue({
    required String key,
    required Map<String, Object?> rawValues,
    required Set<String> dirtyKeys,
    required Map<String, Object?> resolvedValues,
  }) {
    final hasRawValue = rawValues.containsKey(key) && rawValues[key] != null;
    if (dirtyKeys.contains(key) || hasRawValue) {
      final rawValue = rawValues[key];
      if (rawValue != null && rawValue is! T) {
        throw FoundryContextException(
          'Expected a value of type $T for key "$key" but found a value '
          'of type ${rawValue.runtimeType}.',
        );
      }
      return rawValue;
    }

    final derive = defaultValue;
    if (derive == null) return null;
    return derive(
      SnapshotFoundryContext({...resolvedValues, ...rawValues}),
    );
  }

  /// Runs [validators] against [value] and the current [context], returning
  /// each non-null error message in order.
  ///
  /// Throws [FoundryContextException] if [value] is non-null and not a
  /// [T], instead of letting the internal cast fail with an opaque
  /// [TypeError].
  List<String> validate(Object? value, SnapshotFoundryContext context) {
    if (value != null && value is! T) {
      throw FoundryContextException(
        'Expected a value of type $T but found a value of type '
        '${value.runtimeType}.',
      );
    }
    return validators
        .map((validator) => validator(value as T?, context))
        .whereType<String>()
        .toList(growable: false);
  }
}

/// A free-form string variable.
final class FoundryStringVariable extends FoundryVariable<String> {
  /// Creates a [FoundryStringVariable].
  const FoundryStringVariable({
    required super.label,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  });
}

/// A boolean toggle variable.
final class FoundryBooleanVariable extends FoundryVariable<bool> {
  /// Creates a [FoundryBooleanVariable].
  const FoundryBooleanVariable({
    required super.label,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  });
}

/// An integer variable.
final class FoundryIntVariable extends FoundryVariable<int> {
  /// Creates a [FoundryIntVariable].
  const FoundryIntVariable({
    required super.label,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  });
}

/// A floating-point variable.
final class FoundryDoubleVariable extends FoundryVariable<double> {
  /// Creates a [FoundryDoubleVariable].
  const FoundryDoubleVariable({
    required super.label,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  });
}

/// A single-select choice from a fixed set of [options].
///
/// The resolved value type is [T]. [displayLabel] is required so the TUI can
/// render non-string options.
final class FoundrySingleChoiceVariable<T> extends FoundryVariable<T> {
  /// Creates a [FoundrySingleChoiceVariable].
  ///
  /// [options] may be a [Set] or [List]; declaration order is preserved for
  /// TUI rendering.
  FoundrySingleChoiceVariable({
    required super.label,
    required Iterable<T> options,
    required this.displayLabel,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  }) : options = List<T>.unmodifiable(options);

  /// Allowed values for this variable, in declaration order.
  final List<T> options;

  /// Maps an option to the label shown in the variable TUI.
  final FoundryDisplayLabel<T> displayLabel;

  @override
  List<String> validate(Object? value, SnapshotFoundryContext context) {
    if (value != null && value is! T) {
      throw FoundryContextException(
        'Expected a value of type $T but found a value of type '
        '${value.runtimeType}.',
      );
    }

    final typed = value as T?;
    final errors = <String>[
      if (typed != null && !options.contains(typed))
        'Value is not a valid option.',
    ];
    errors.addAll(
      validators
          .map((validator) => validator(typed, context))
          .whereType<String>(),
    );
    return errors;
  }
}

/// A multi-select choice from a fixed set of [options].
///
/// The resolved value type is [List<T>]. Selected values are normalized to
/// [options] declaration order (duplicates removed). An empty selection is
/// allowed unless [validators] reject it. [displayLabel] is required so the
/// TUI can render non-string options.
final class FoundryMultipleChoiceVariable<T> extends FoundryVariable<List<T>> {
  /// Creates a [FoundryMultipleChoiceVariable].
  ///
  /// [options] may be a [Set] or [List]; declaration order is preserved for
  /// TUI rendering and for the resolved [List] order.
  FoundryMultipleChoiceVariable({
    required super.label,
    required Iterable<T> options,
    required this.displayLabel,
    super.visibleWhen,
    super.enabledWhen,
    super.defaultValue,
    super.validators,
    super.description,
    super.placeholder,
    super.help,
  }) : options = List<T>.unmodifiable(options);

  /// Allowed values for this variable, in declaration order.
  final List<T> options;

  /// Maps an option to the label shown in the variable TUI.
  final FoundryDisplayLabel<T> displayLabel;

  @override
  Object? resolveValue({
    required String key,
    required Map<String, Object?> rawValues,
    required Set<String> dirtyKeys,
    required Map<String, Object?> resolvedValues,
  }) {
    final hasRawValue = rawValues.containsKey(key) && rawValues[key] != null;
    if (dirtyKeys.contains(key) || hasRawValue) {
      final rawValue = rawValues[key];
      if (rawValue == null) {
        return null;
      }
      return _normalizeSelection(
        key: key,
        rawValue: rawValue,
      );
    }

    final derive = defaultValue;
    if (derive == null) {
      return null;
    }
    return _orderSelection(
      derive(
        SnapshotFoundryContext({...resolvedValues, ...rawValues}),
      ),
    );
  }

  @override
  List<String> validate(Object? value, SnapshotFoundryContext context) {
    if (value == null) {
      return validators
          .map((validator) => validator(null, context))
          .whereType<String>()
          .toList(growable: false);
    }

    final selection = _coerceSelection(value);
    final errors = <String>[
      if (selection.any((element) => !options.contains(element)))
        'Value is not a valid option.',
    ];
    errors.addAll(
      validators
          .map((validator) => validator(selection, context))
          .whereType<String>(),
    );
    return errors;
  }

  List<T> _normalizeSelection({
    required String key,
    required Object rawValue,
  }) {
    if (rawValue is! List) {
      throw FoundryContextException(
        'Expected a value of type List<$T> for key "$key" but found a value '
        'of type ${rawValue.runtimeType}.',
      );
    }

    final selected = <T>[];
    for (final element in rawValue) {
      if (element is! T) {
        throw FoundryContextException(
          'Expected list elements of type $T for key "$key" but found a '
          'value of type ${element.runtimeType}.',
        );
      }
      selected.add(element);
    }
    return _orderSelection(selected);
  }

  List<T> _coerceSelection(Object value) {
    if (value is! List) {
      throw FoundryContextException(
        'Expected a value of type List<$T> but found a value of type '
        '${value.runtimeType}.',
      );
    }

    final selected = <T>[];
    for (final element in value) {
      if (element is! T) {
        throw FoundryContextException(
          'Expected list elements of type $T but found a value of type '
          '${element.runtimeType}.',
        );
      }
      selected.add(element);
    }
    return selected;
  }

  /// Returns [selected] in [options] declaration order.
  ///
  /// Unknown values (not in [options]) are appended in first-seen order so
  /// [validate] can reject them instead of silently dropping them.
  List<T> _orderSelection(Iterable<T> selected) {
    final selectedList = List<T>.of(selected);
    final selectedSet = selectedList.toSet();
    final orderedKnown = [
      for (final option in options)
        if (selectedSet.contains(option)) option,
    ];
    final knownSet = orderedKnown.toSet();
    final unknowns = <T>[];
    final seenUnknown = <T>{};
    for (final value in selectedList) {
      if (!knownSet.contains(value) && seenUnknown.add(value)) {
        unknowns.add(value);
      }
    }
    return [...orderedKnown, ...unknowns];
  }
}
