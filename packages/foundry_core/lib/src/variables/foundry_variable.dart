import 'package:meta/meta.dart';

/// Base type for variables declared in a mold's `variables.dart`.
///
/// Concrete variable kinds are added incrementally as the runtime expands;
/// this release only requires a minimal contract so molds can export the
/// required variable group symbol.
@immutable
sealed class FoundryVariable<T> {
  /// Creates a [FoundryVariable].
  const FoundryVariable({
    required this.label,
  });

  /// Human-readable label shown in the variable TUI.
  final String label;
}

/// A free-form string variable.
final class FoundryStringVariable extends FoundryVariable<String> {
  /// Creates a [FoundryStringVariable].
  const FoundryStringVariable({
    required super.label,
  });
}
