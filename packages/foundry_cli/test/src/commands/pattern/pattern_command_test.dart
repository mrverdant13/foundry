import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/pattern/pattern_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:test/test.dart';

void main() {
  group('PatternCommand', () {
    test('registers the init subcommand', () {
      final command = PatternCommand(logger: Logger());

      expect(command.subcommands.keys, contains('init'));
    });

    test('reports a usage error when no subcommand is given', () async {
      final runner = CommandRunner<int>('foundry', 'test runner')
        ..addCommand(PatternCommand(logger: Logger()));

      await expectLater(
        runner.run(['pattern']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('Missing subcommand'),
          ),
        ),
      );
    });
  });
}
