import 'dart:io';

import 'package:foundry_core/src/context/snapshot_foundry_context.dart';
import 'package:foundry_core/src/logging/logger.dart';

/// Mutable cast context passed to lifecycle hooks (`prepare`, `shape`,
/// `finish`).
///
/// Extends [SnapshotFoundryContext], inheriting its strict `required*` /
/// `optional*` read accessors, and adds [set], [merge], and [remove] to
/// mutate cast values plus the hook environment fields [logger],
/// [moldDirectory], and [outputDirectory].
///
/// There is no public map of values — mold authors read and write through
/// these accessors and mutation methods only.
class FoundryContext extends SnapshotFoundryContext {
  /// Creates a [FoundryContext] seeded with the current gathered [values]
  /// and the hook environment it runs in.
  FoundryContext({
    required this.logger,
    required this.moldDirectory,
    required this.outputDirectory,
    Map<String, Object?> values = const {},
  })  : _values = Map.of(values),
        super(values);

  final Map<String, Object?> _values;

  /// Info / warn / error / progress output for the running hook.
  final Logger logger;

  /// Root directory of the mold being cast.
  final Directory moldDirectory;

  /// The `--output` directory (working directory for the `finish` hook).
  final Directory outputDirectory;

  @override
  Map<String, Object?> get currentValues => _values;

  /// Sets or replaces the value for [key].
  void set(String key, Object? value) => _values[key] = value;

  /// Merges [values] into the current cast values, overwriting existing
  /// keys.
  void merge(Map<String, Object?> values) => _values.addAll(values);

  /// Removes the value for [key], if present.
  void remove(String key) => _values.remove(key);

  /// A read-only [SnapshotFoundryContext] reflecting the current values.
  ///
  /// Used by the runtime to evaluate variable callbacks (`visibleWhen`,
  /// `defaultValue`, validators) against the latest hook mutations.
  SnapshotFoundryContext snapshot() => SnapshotFoundryContext(_values);
}
