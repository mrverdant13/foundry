import 'package:foundry_core/src/variables/foundry_variable.dart';
import 'package:meta/meta.dart';

/// Code-first variable schema exported from a mold's variables definition file.
@immutable
final class FoundryVariableGroup {
  /// Creates a [FoundryVariableGroup].
  const FoundryVariableGroup({
    required this.variables,
  });

  /// Variable definitions keyed by context field name.
  final Map<String, FoundryVariable<dynamic>> variables;
}
