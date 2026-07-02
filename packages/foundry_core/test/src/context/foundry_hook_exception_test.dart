import 'package:foundry_core/src/context/foundry_hook_exception.dart';
import 'package:test/test.dart';

void main() {
  test('FoundryHookException implements Exception', () {
    const exception = FoundryHookException('Aborted by mold author.');

    expect(exception, isA<Exception>());
    expect(exception.message, 'Aborted by mold author.');
  });

  test('FoundryHookException toString includes the message', () {
    const exception = FoundryHookException('Missing required input.');

    expect(
      exception.toString(),
      'FoundryHookException: Missing required input.',
    );
  });
}
