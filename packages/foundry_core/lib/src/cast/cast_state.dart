import 'package:meta/meta.dart';

/// Persisted state of the last successful `foundry cast`, written to
/// `.foundry/last_cast.json` in the process cwd.
///
/// Read back by `foundry recast` (re-runs the full cast pipeline with the
/// same [moldPath], [outputPath], and [vars]) and `foundry finish` (runs
/// only the mold's finish hook with [outputPath] as its working directory).
@immutable
final class CastState {
  /// Creates a [CastState].
  const CastState({
    required this.moldPath,
    required this.outputPath,
    required this.vars,
    required this.timestamp,
  });

  /// Parses a [CastState] from a decoded `last_cast.json` object.
  ///
  /// Throws a [TypeError] if a required field is missing or holds a value
  /// of the wrong type, or a [FormatException] if [timestamp] is not a
  /// valid ISO-8601 string.
  factory CastState.fromJson(Map<String, Object?> json) {
    return CastState(
      moldPath: json['moldPath']! as String,
      outputPath: json['outputPath']! as String,
      vars: Map<String, Object?>.from(json['vars']! as Map),
      timestamp: DateTime.parse(json['timestamp']! as String),
    );
  }

  /// Path to the mold that was cast, exactly as supplied to `foundry cast`.
  final String moldPath;

  /// Path the mold was cast into, exactly as supplied to `foundry cast`.
  final String outputPath;

  /// Gathered cast values, as plain JSON: primitives (`String`, `num`,
  /// `bool`, `null`) or nested JSON structures for object-valued variables.
  /// No per-value type tags — on `recast`, these seed a fresh
  /// `FoundryContext` before the cast pipeline runs again.
  final Map<String, Object?> vars;

  /// When the cast this state describes completed successfully.
  final DateTime timestamp;

  /// Encodes this state to the JSON shape written to `last_cast.json`.
  Map<String, Object?> toJson() => {
        'moldPath': moldPath,
        'outputPath': outputPath,
        'vars': vars,
        'timestamp': timestamp.toIso8601String(),
      };
}
