import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test('MoldDeriveException toString includes the message', () {
    const exception = MoldDeriveException('Destination already exists.');

    expect(
      exception.toString(),
      'MoldDeriveException: Destination already exists.',
    );
  });
}
