import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test('MoldSyncException toString includes the message', () {
    const exception = MoldSyncException('Path is not a mold.');

    expect(
      exception.toString(),
      'MoldSyncException: Path is not a mold.',
    );
  });
}
