import 'package:foundry_core/src/mold/mold_hook_exception.dart';

/// Normalizes hook failure text for [MoldHookException.message].
///
/// Shared by the subprocess runner (stderr) and the in-process runner
/// (`Object.toString()`), so both paths strip empty lines, the
/// `Unhandled exception:` banner, and `#…` stack frames, then join the
/// remaining lines into a single message.
String normalizeMoldHookFailureText(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final messageLines = <String>[];
  for (final line in trimmed.split('\n')) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith('#')) break;
    if (trimmedLine.isEmpty || trimmedLine == 'Unhandled exception:') {
      continue;
    }
    messageLines.add(trimmedLine);
  }

  return messageLines.isEmpty ? trimmed : messageLines.join(' ');
}
