import 'package:foundry_core/src/mold/mold_hook_failure.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeMoldHookFailureText', () {
    test('returns empty input unchanged after trim', () {
      expect(normalizeMoldHookFailureText('  \n  '), '');
    });

    test('joins multi-line messages and drops the unhandled banner', () {
      expect(
        normalizeMoldHookFailureText('''
Unhandled exception:
FoundryHookException: first
second detail
'''),
        'FoundryHookException: first second detail',
      );
    });

    test('stops before stack-trace lines', () {
      expect(
        normalizeMoldHookFailureText('''
FoundryHookException: boom
#0      main (file:///tmp/hook.dart:3:3)
#1      _startIsolate (dart:isolate-patch/isolate_patch.dart:1:1)
'''),
        'FoundryHookException: boom',
      );
    });
  });
}
