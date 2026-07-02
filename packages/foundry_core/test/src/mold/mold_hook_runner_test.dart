import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_hook_runner.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_test_support.dart';

void main() {
  late Directory moldDirectory;
  late Directory hooksDirectory;
  late Directory outputDirectory;

  setUpAll(() async {
    moldDirectory =
        await Directory.systemTemp.createTemp('foundry_hook_runner_mold_');
    await writeMoldPubspec(
      directory: moldDirectory,
      name: 'hook_runner_demo',
      description: 'Mold used to exercise the hook process runner',
    );
    hooksDirectory =
        await Directory(p.join(moldDirectory.path, MoldHooks.directory))
            .create();
    await ensureMoldDependencies(moldDirectory);
  });

  tearDownAll(() => moldDirectory.deleteSync(recursive: true));

  setUp(() async {
    outputDirectory =
        await Directory.systemTemp.createTemp('foundry_hook_runner_output_');
  });

  tearDown(() => outputDirectory.deleteSync(recursive: true));

  FoundryContext buildContext({
    Map<String, Object?> values = const {},
    Logger? logger,
  }) {
    return FoundryContext(
      values: values,
      logger: logger ?? Logger(),
      moldDirectory: moldDirectory,
      outputDirectory: outputDirectory,
    );
  }

  Future<void> writeHook(String relativePath, String contents) {
    return File(p.join(moldDirectory.path, relativePath))
        .writeAsString(contents);
  }

  group('runMoldHook', () {
    test('is a no-op when hookFile is null', () async {
      final context = buildContext(values: const {'a': 1});

      await runMoldHook(
        phase: MoldHookPhase.prepare,
        hookFile: null,
        context: context,
      );

      expect(context.entries, {'a': 1});
    });

    test('is a no-op when the hook file does not exist', () async {
      final context = buildContext(values: const {'a': 1});
      final missingHook = File(
        p.join(hooksDirectory.path, 'does_not_exist.dart'),
      );

      await runMoldHook(
        phase: MoldHookPhase.prepare,
        hookFile: missingHook,
        context: context,
      );

      expect(context.entries, {'a': 1});
    });

    test('applies the hook process mutations to the context', () async {
      await writeHook(MoldHooks.preparePath, r'''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('greeting', 'hi ${context.requiredString('name')}');
  context.remove('name');
}
''');
      final hookFile = File(p.join(moldDirectory.path, MoldHooks.preparePath));
      final context = buildContext(values: const {'name': 'Ada'});

      await runMoldHook(
        phase: MoldHookPhase.prepare,
        hookFile: hookFile,
        context: context,
      );

      expect(context.contains('name'), isFalse);
      expect(context.requiredString('greeting'), 'hi Ada');
    });

    test('forwards hook stdout through the logger', () async {
      await writeHook(MoldHooks.shapePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.logger.info('hello from hook');
}
''');
      final hookFile = File(p.join(moldDirectory.path, MoldHooks.shapePath));
      final messages = <String>[];
      final context = buildContext(
        logger: Logger(onInfo: messages.add),
      );

      await runMoldHook(
        phase: MoldHookPhase.shape,
        hookFile: hookFile,
        context: context,
      );

      expect(messages, contains('hello from hook'));
    });

    test('runs the hook process with the output directory as cwd', () async {
      await writeHook(MoldHooks.finishPath, '''
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('cwd', Directory.current.path);
}
''');
      final hookFile = File(p.join(moldDirectory.path, MoldHooks.finishPath));
      final context = buildContext();

      await runMoldHook(
        phase: MoldHookPhase.finish,
        hookFile: hookFile,
        context: context,
      );

      final reportedCwd =
          Directory(context.requiredString('cwd')).resolveSymbolicLinksSync();
      expect(reportedCwd, outputDirectory.resolveSymbolicLinksSync());
    });

    test(
        'throws MoldHookException when the hook throws '
        'FoundryHookException', () async {
      await writeHook(MoldHooks.shapePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  throw const FoundryHookException('nope');
}
''');
      final hookFile = File(p.join(moldDirectory.path, MoldHooks.shapePath));
      final context = buildContext();

      await expectLater(
        runMoldHook(
          phase: MoldHookPhase.shape,
          hookFile: hookFile,
          context: context,
        ),
        throwsA(
          isA<MoldHookException>()
              .having((error) => error.phase, 'phase', MoldHookPhase.shape)
              .having((error) => error.hookPath, 'hookPath', hookFile.path)
              .having(
                (error) => error.message,
                'message',
                allOf(contains('FoundryHookException'), contains('nope')),
              ),
        ),
      );
    });

    test(
        'throws MoldHookException when the context values cannot be '
        'JSON-encoded', () async {
      await writeHook(MoldHooks.finishPath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {}
''');
      final hookFile = File(p.join(moldDirectory.path, MoldHooks.finishPath));
      final context = buildContext(values: {'when': DateTime.now()});

      await expectLater(
        runMoldHook(
          phase: MoldHookPhase.finish,
          hookFile: hookFile,
          context: context,
        ),
        throwsA(
          isA<MoldHookException>()
              .having((error) => error.phase, 'phase', MoldHookPhase.finish)
              .having((error) => error.hookPath, 'hookPath', hookFile.path)
              .having(
                (error) => error.message,
                'message',
                contains('Failed to prepare hook input'),
              ),
        ),
      );
    });

    test('throws MoldHookException when the mold package config is missing',
        () async {
      final unresolvedMoldDirectory = await Directory.systemTemp.createTemp(
        'foundry_hook_runner_unresolved_',
      );
      addTearDown(() => unresolvedMoldDirectory.deleteSync(recursive: true));
      await writeMoldPubspec(
        directory: unresolvedMoldDirectory,
        name: 'unresolved',
        description: 'Mold without a resolved package config',
      );
      final hooksDir = await Directory(
        p.join(unresolvedMoldDirectory.path, MoldHooks.directory),
      ).create();
      final hookFile = File(p.join(hooksDir.path, MoldHooks.finish))
        ..writeAsStringSync('//');
      final context = FoundryContext(
        logger: Logger(),
        moldDirectory: unresolvedMoldDirectory,
        outputDirectory: outputDirectory,
      );

      await expectLater(
        runMoldHook(
          phase: MoldHookPhase.finish,
          hookFile: hookFile,
          context: context,
        ),
        throwsA(
          isA<MoldHookException>().having(
            (error) => error.message,
            'message',
            contains('package config'),
          ),
        ),
      );
    });
  });

  group('readMoldHookOutcome', () {
    test('throws when the output file does not exist', () {
      final outputFile = File(
        p.join(outputDirectory.path, 'does_not_exist.json'),
      );

      expect(
        () => readMoldHookOutcome(
          phase: MoldHookPhase.prepare,
          hookPath: 'hooks/prepare.dart',
          outputFile: outputFile,
        ),
        throwsA(
          isA<MoldHookException>().having(
            (error) => error.message,
            'message',
            contains('did not produce an output payload'),
          ),
        ),
      );
    });

    test('throws when the output file contains malformed JSON', () {
      final outputFile = File(p.join(outputDirectory.path, 'output.json'))
        ..writeAsStringSync('not json');

      expect(
        () => readMoldHookOutcome(
          phase: MoldHookPhase.prepare,
          hookPath: 'hooks/prepare.dart',
          outputFile: outputFile,
        ),
        throwsA(
          isA<MoldHookException>().having(
            (error) => error.message,
            'message',
            contains('invalid output payload'),
          ),
        ),
      );
    });

    test('throws when the output file decodes to a non-object value', () {
      final outputFile = File(p.join(outputDirectory.path, 'output.json'))
        ..writeAsStringSync('[1, 2, 3]');

      expect(
        () => readMoldHookOutcome(
          phase: MoldHookPhase.prepare,
          hookPath: 'hooks/prepare.dart',
          outputFile: outputFile,
        ),
        throwsA(
          isA<MoldHookException>().having(
            (error) => error.message,
            'message',
            contains('invalid output payload'),
          ),
        ),
      );
    });

    test('returns the decoded map for a valid JSON object', () {
      final outputFile = File(p.join(outputDirectory.path, 'output.json'))
        ..writeAsStringSync('{"greeting": "hi"}');

      final decoded = readMoldHookOutcome(
        phase: MoldHookPhase.prepare,
        hookPath: 'hooks/prepare.dart',
        outputFile: outputFile,
      );

      expect(decoded, {'greeting': 'hi'});
    });
  });
}
