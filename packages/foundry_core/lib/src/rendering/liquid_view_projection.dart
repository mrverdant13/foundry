import 'dart:collection';

import 'package:foundry_core/src/rendering/foundry_liquid_view.dart';
import 'package:liquify/liquify.dart';

/// Thrown when a cast context value cannot be projected for Liquid rendering.
final class LiquidViewProjectionException implements Exception {
  /// Creates a [LiquidViewProjectionException] with a human-readable [message].
  const LiquidViewProjectionException(this.message);

  /// Human-readable description of the projection problem.
  final String message;

  @override
  String toString() => 'LiquidViewProjectionException: $message';
}

/// Projects [values] into a Liquid-compatible map for template rendering.
///
/// Accepted leaves: `null`, [bool], [String], [num], liquify [Drop], and
/// [FoundryLiquidView] (via [FoundryLiquidView.toLiquid], then projected).
/// [List] and string-keyed [Map] values are projected recursively.
///
/// Anything else — including Dart [Enum] values and maps with non-string keys —
/// fails loudly. Cycles are detected by object identity and reported with a
/// dotted context path (for example `repo.owner`).
Map<String, dynamic> projectLiquidView(Map<String, Object?> values) {
  final visiting = IdentityHashMap<Object, bool>();
  final projected = <String, dynamic>{};
  for (final entry in values.entries) {
    projected[entry.key] = _projectValue(entry.value, entry.key, visiting);
  }
  return projected;
}

Object? _projectValue(
  Object? value,
  String path,
  IdentityHashMap<Object, bool> visiting,
) {
  if (value == null || value is bool || value is String || value is num) {
    return value;
  }

  if (value is Drop) {
    return value;
  }

  if (value is FoundryLiquidView) {
    _enter(value, path, visiting);
    try {
      return _projectValue(value.toLiquid(), path, visiting);
    } finally {
      visiting.remove(value);
    }
  }

  if (value is List) {
    _enter(value, path, visiting);
    try {
      return [
        for (var i = 0; i < value.length; i++)
          _projectValue(value[i], '$path[$i]', visiting),
      ];
    } finally {
      visiting.remove(value);
    }
  }

  if (value is Map) {
    _enter(value, path, visiting);
    try {
      final projected = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw LiquidViewProjectionException(
            'Cannot project map at "$path": key has type '
            '${key.runtimeType}, expected String.',
          );
        }
        final childPath = path.isEmpty ? key : '$path.$key';
        projected[key] = _projectValue(entry.value, childPath, visiting);
      }
      return projected;
    } finally {
      visiting.remove(value);
    }
  }

  throw LiquidViewProjectionException(
    'Cannot project value at "$path" of type ${value.runtimeType} for '
    'Liquid templates.',
  );
}

void _enter(
  Object value,
  String path,
  IdentityHashMap<Object, bool> visiting,
) {
  if (visiting.containsKey(value)) {
    throw LiquidViewProjectionException(
      'Cycle detected while projecting Liquid view at "$path".',
    );
  }
  visiting[value] = true;
}
