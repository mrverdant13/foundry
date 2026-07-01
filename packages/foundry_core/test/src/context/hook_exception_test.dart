import 'package:foundry_core/src/context/hook_exception.dart';
import 'package:test/test.dart';

void main() {
  test('HookException implements Exception', () {
    const exception = HookException('Aborted by mold author.');

    expect(exception, isA<Exception>());
    expect(exception.message, 'Aborted by mold author.');
  });

  test('HookException toString includes the message', () {
    const exception = HookException('Missing required input.');

    expect(
      exception.toString(),
      'HookException: Missing required input.',
    );
  });
}
