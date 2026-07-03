import 'package:foundry_cli/src/exit_code.dart';
import 'package:test/test.dart';

void main() {
  group('FoundryExitCode', () {
    test('success is 0', () {
      expect(FoundryExitCode.success.code, 0);
    });

    test('userError is 1', () {
      expect(FoundryExitCode.userError.code, 1);
    });

    test('internalError is 2', () {
      expect(FoundryExitCode.internalError.code, 2);
    });
  });
}
