import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:meta/meta.dart';

/// Read-only view of the values gathered during a cast.
///
/// Base type for variable callbacks declared in a mold's `variables.dart`
/// (`visibleWhen`, `defaultValue`, per-variable `validators`, and
/// `groupValidators`). Exposes strict `required*` / `optional*` accessors
/// (plus a read-only snapshot via [entries]) — no mutation methods and no hook
/// environment fields.
///
/// `required*` accessors throw [FoundryContextException] when a key is
/// missing, null, or holds a value of the wrong runtime type. `optional*`
/// accessors return `null` when a key is missing or null, and throw
/// [FoundryContextException] only when the value has the wrong runtime type.
@immutable
class SnapshotFoundryContext {
  /// Creates a [SnapshotFoundryContext] from the current gathered [values].
  SnapshotFoundryContext(Map<String, Object?> values)
      : _values = Map.unmodifiable(values);

  final Map<String, Object?> _values;

  /// Whether [key] is present in the current cast values.
  bool contains(String key) => _values.containsKey(key);

  /// Returns the value for [key] as a `String?`.
  ///
  /// Returns `null` if [key] is absent or its value is `null`. Throws
  /// [FoundryContextException] if the value is not a `String`.
  String? optionalString(String key) => optional<String>(key);

  /// Returns the value for [key] as a non-null `String`.
  ///
  /// Throws [FoundryContextException] if [key] is absent, its value is
  /// `null`, or the value is not a `String`.
  String requiredString(String key) => required<String>(key);

  /// Returns the value for [key] as a `bool?`.
  ///
  /// Returns `null` if [key] is absent or its value is `null`. Throws
  /// [FoundryContextException] if the value is not a `bool`.
  bool? optionalBool(String key) => optional<bool>(key);

  /// Returns the value for [key] as a non-null `bool`.
  ///
  /// Throws [FoundryContextException] if [key] is absent, its value is
  /// `null`, or the value is not a `bool`.
  bool requiredBool(String key) => required<bool>(key);

  /// Returns the value for [key] as an `int?`.
  ///
  /// Returns `null` if [key] is absent or its value is `null`. Throws
  /// [FoundryContextException] if the value is not an `int`.
  int? optionalInt(String key) => optional<int>(key);

  /// Returns the value for [key] as a non-null `int`.
  ///
  /// Throws [FoundryContextException] if [key] is absent, its value is
  /// `null`, or the value is not an `int`.
  int requiredInt(String key) => required<int>(key);

  /// Returns the value for [key] as a `double?`.
  ///
  /// Returns `null` if [key] is absent or its value is `null`. Throws
  /// [FoundryContextException] if the value is not a `double`.
  double? optionalDouble(String key) => optional<double>(key);

  /// Returns the value for [key] as a non-null `double`.
  ///
  /// Throws [FoundryContextException] if [key] is absent, its value is
  /// `null`, or the value is not a `double`.
  double requiredDouble(String key) => required<double>(key);

  /// Returns the value for [key] as a `T?`, for custom seeded objects.
  ///
  /// Returns `null` if [key] is absent or its value is `null`. Throws
  /// [FoundryContextException] if the value is not a `T`.
  T? optional<T>(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value == null) return null;
    return _cast<T>(key, value);
  }

  /// Returns the value for [key] as a non-null `T`, for custom seeded
  /// objects.
  ///
  /// Throws [FoundryContextException] if [key] is absent, its value is
  /// `null`, or the value is not a `T`.
  T required<T>(String key) {
    if (!_values.containsKey(key) || _values[key] == null) {
      throw FoundryContextException(
        'Missing required value for key "$key".',
      );
    }
    return _cast<T>(key, _values[key]);
  }

  T _cast<T>(String key, Object? value) {
    if (value is T) return value;
    throw FoundryContextException(
      'Expected a value of type $T for key "$key" but found a value of '
      'type ${value.runtimeType}.',
    );
  }

  /// Read-only snapshot of the current cast values.
  ///
  /// Not intended for use outside this package even though it is reachable via
  /// the public API export.
  @internal
  Map<String, Object?> get entries => _values;
}
