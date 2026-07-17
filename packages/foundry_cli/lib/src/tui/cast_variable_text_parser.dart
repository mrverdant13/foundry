import 'package:foundry_core/foundry_core.dart';

/// Result of parsing a TUI text field into a typed cast variable value.
sealed class CastVariableTextParseResult {
  const CastVariableTextParseResult();
}

/// Successful parse of field text into [value]
/// (which may be `null` when empty).
final class CastVariableTextParseSuccess extends CastVariableTextParseResult {
  /// Creates a [CastVariableTextParseSuccess].
  const CastVariableTextParseSuccess(this.value);

  /// The typed raw value to pass into variable evaluation.
  final Object? value;
}

/// Failed parse of field text for the target variable kind.
final class CastVariableTextParseFailure extends CastVariableTextParseResult {
  /// Creates a [CastVariableTextParseFailure].
  const CastVariableTextParseFailure(this.message);

  /// Human-readable parse error shown in-form.
  final String message;
}

/// Parses TUI text input into a typed raw value for [variable].
///
/// Empty or whitespace-only input yields a successful `null` value so defaults
/// and validators can run. Invalid numeric or boolean text yields a
/// [CastVariableTextParseFailure] instead of a mistyped raw value that would
/// throw during evaluation.
CastVariableTextParseResult parseCastVariableText(
  FoundryVariable<dynamic> variable,
  String text,
) {
  final trimmed = text.trim();
  return switch (variable) {
    FoundryStringVariable() => CastVariableTextParseSuccess(text),
    FoundryBooleanVariable() => _parseBoolean(trimmed),
    FoundryIntVariable() => _parseInt(trimmed),
    FoundryDoubleVariable() => _parseDouble(trimmed),
  };
}

CastVariableTextParseResult _parseBoolean(String trimmed) {
  if (trimmed.isEmpty) {
    return const CastVariableTextParseSuccess(null);
  }
  final normalized = trimmed.toLowerCase();
  return switch (normalized) {
    'true' || 'yes' || 'y' || '1' => const CastVariableTextParseSuccess(true),
    'false' || 'no' || 'n' || '0' => const CastVariableTextParseSuccess(false),
    _ => const CastVariableTextParseFailure('Enter yes/no or true/false'),
  };
}

CastVariableTextParseResult _parseInt(String trimmed) {
  if (trimmed.isEmpty) {
    return const CastVariableTextParseSuccess(null);
  }
  final value = int.tryParse(trimmed);
  if (value == null) {
    return const CastVariableTextParseFailure('Enter a valid integer');
  }
  return CastVariableTextParseSuccess(value);
}

CastVariableTextParseResult _parseDouble(String trimmed) {
  if (trimmed.isEmpty) {
    return const CastVariableTextParseSuccess(null);
  }
  final value = double.tryParse(trimmed);
  if (value == null) {
    return const CastVariableTextParseFailure('Enter a valid number');
  }
  return CastVariableTextParseSuccess(value);
}
