import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test('MoldImportException toString includes the message', () {
    const exception = MoldImportException('Destination already exists.');

    expect(
      exception.toString(),
      'MoldImportException: Destination already exists.',
    );
  });
}
