/// Builds a JSON-encodable projection of cast context values for persistence.
///
/// Matches the shape written to `.foundry/last_cast.json`: JSON primitives
/// (`null`, `bool`, `num`, `String`), arrays, and nested objects with string
/// keys. Non-encodable values (custom Dart objects, non-string map keys) are
/// omitted so prepare-seeded private objects never enter cast state.
Map<String, Object?> projectEncodableCastVars(Map<String, Object?> values) {
  final projected = <String, Object?>{};
  for (final entry in values.entries) {
    final value = _projectEncodableValue(entry.value);
    if (!identical(value, _omit)) {
      projected[entry.key] = value;
    }
  }
  return Map.unmodifiable(projected);
}

const Object _omit = Object();

Object? _projectEncodableValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return [
      for (final element in value) _projectListElement(element),
    ];
  }
  if (value is Map) {
    final projected = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final projectedValue = _projectEncodableValue(entry.value);
      if (!identical(projectedValue, _omit)) {
        projected[key] = projectedValue;
      }
    }
    return projected;
  }
  return _omit;
}

Object? _projectListElement(Object? element) {
  final projected = _projectEncodableValue(element);
  // Preserve list length/indices; non-encodable slots become null.
  return identical(projected, _omit) ? null : projected;
}
