import 'package:args/command_runner.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/foundry_command_runner.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:foundry_core/foundry_core.dart' show Logger;
import 'package:test/test.dart';

/// A command that always throws, used to exercise the runner's handling of
/// unexpected (non-[UsageException]) errors raised while running a command.
class _ThrowingCommand extends Command<int> {
  @override
  String get name => 'boom';

  @override
  String get description => 'Always throws.';

  @override
  Future<int> run() async => throw StateError('unexpected failure');
}

void main() {
  group('FoundryCommandRunner', () {
    test('registers the mold resource command', () {
      final runner = FoundryCommandRunner();

      expect(runner.commands.keys, contains('mold'));
    });

    test('--version prints the current package version and exits 0', () async {
      final infoMessages = <String>[];
      final runner = FoundryCommandRunner(
        logger: Logger(onInfo: infoMessages.add),
      );

      final exitCode = await runner.run(['--version']);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, contains(foundryCliVersion));
    });

    test('no arguments prints usage and exits 0', () async {
      final infoMessages = <String>[];
      final runner = FoundryCommandRunner(
        logger: Logger(onInfo: infoMessages.add),
      );

      final exitCode = await runner.run([]);

      expect(exitCode, FoundryExitCode.success.code);
      expect(infoMessages, isNotEmpty);
    });

    test('an unknown command prints usage to stderr and exits non-zero',
        () async {
      final errorMessages = <String>[];
      final infoMessages = <String>[];
      final runner = FoundryCommandRunner(
        logger: Logger(
          onError: errorMessages.add,
          onInfo: infoMessages.add,
        ),
      );

      final exitCode = await runner.run(['not-a-real-command']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(
        errorMessages,
        contains(contains('not-a-real-command')),
      );
      expect(errorMessages, contains(contains('Usage:')));
      expect(infoMessages, isEmpty);
    });

    test('falls back to a default logger when none is provided', () async {
      final runner = FoundryCommandRunner();

      final exitCode = await runner.run(['--version']);

      expect(exitCode, FoundryExitCode.success.code);
    });

    test('an invalid flag prints usage to stderr and exits non-zero', () async {
      final errorMessages = <String>[];
      final infoMessages = <String>[];
      final runner = FoundryCommandRunner(
        logger: Logger(
          onError: errorMessages.add,
          onInfo: infoMessages.add,
        ),
      );

      final exitCode = await runner.run(['--not-a-real-flag']);

      expect(exitCode, FoundryExitCode.userError.code);
      expect(errorMessages, contains(contains('Usage:')));
      expect(infoMessages, isEmpty);
    });

    test(
        'an unexpected error from a command is reported and exits with '
        'the internal error code', () async {
      final errorMessages = <String>[];
      final runner = FoundryCommandRunner(
        logger: Logger(onError: errorMessages.add),
      )..addCommand(_ThrowingCommand());

      final exitCode = await runner.run(['boom']);

      expect(exitCode, FoundryExitCode.internalError.code);
      expect(
        errorMessages,
        contains(contains('unexpected failure')),
      );
    });
  });
}
