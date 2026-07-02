import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test('toString includes phase, hook path, and message', () {
    const exception = MoldHookException(
      phase: MoldHookPhase.shape,
      hookPath: 'hooks/shape.dart',
      message: 'boom',
    );

    expect(
      exception.toString(),
      'MoldHookException(shape, hooks/shape.dart): boom',
    );
  });
}
