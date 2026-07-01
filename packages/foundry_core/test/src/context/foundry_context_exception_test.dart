import 'package:foundry_core/src/context/foundry_context_exception.dart';
import 'package:test/test.dart';

void main() {
  test('FoundryContextException implements Exception', () {
    const exception = FoundryContextException('Something went wrong.');

    expect(exception, isA<Exception>());
    expect(exception.message, 'Something went wrong.');
  });

  test('FoundryContextException toString includes the message', () {
    const exception = FoundryContextException('Missing required value.');

    expect(
      exception.toString(),
      'FoundryContextException: Missing required value.',
    );
  });
}
