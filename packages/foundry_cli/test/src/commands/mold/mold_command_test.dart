import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:test/test.dart';

void main() {
  group('MoldCommand', () {
    test('registers the init, inspect, derive, sync, and import subcommands',
        () {
      final command = MoldCommand(logger: Logger());

      expect(
        command.subcommands.keys,
        containsAll(['init', 'inspect', 'derive', 'sync', 'import']),
      );
    });

    test('reports a usage error when no subcommand is given', () async {
      final runner = CommandRunner<int>('foundry', 'test runner')
        ..addCommand(MoldCommand(logger: Logger()));

      await expectLater(
        runner.run(['mold']),
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
