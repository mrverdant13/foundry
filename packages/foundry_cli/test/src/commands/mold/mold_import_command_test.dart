import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/commands/mold/mold_import_command.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:test/test.dart';

void main() {
  group('MoldImportCommand', () {
    test('registers the git and local subcommands', () {
      final command = MoldImportCommand(logger: Logger());

      expect(command.subcommands.keys, containsAll(['git', 'local']));
    });

    test('reports a usage error when no subcommand is given', () async {
      final runner = CommandRunner<int>('foundry', 'test runner')
        ..addCommand(MoldImportCommand(logger: Logger()));

      await expectLater(
        runner.run(['import']),
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
