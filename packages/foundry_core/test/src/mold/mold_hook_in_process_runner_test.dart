import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/hooks/mutate_context.dart' as mutate_context;
import 'fixtures/hooks/preserve_seeded_object.dart' as preserve_seeded_object;
import 'fixtures/hooks/report_cwd.dart' as report_cwd;
import 'fixtures/hooks/throw_foundry_hook_exception.dart'
    as throw_foundry_hook_exception;
import 'mold_test_support.dart';

void main() {
  late Directory moldDirectory;
  late Directory hooksDirectory;
  late Directory outputDirectory;

  setUpAll(() async {
    moldDirectory = await Directory.systemTemp.createTemp(
      'foundry_in_process_hook_mold_',
    );
    hooksDirectory =
        await Directory(p.join(moldDirectory.path, MoldHooks.directory))
            .create();
  });

  tearDownAll(() => moldDirectory.deleteSync(recursive: true));

  setUp(() async {
    outputDirectory = await Directory.systemTemp.createTemp(
      'foundry_in_process_hook_output_',
    );
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

  File fixtureHook(String fileName) {
    return File(
      p.join(
        foundryCorePackageRoot().path,
        'test',
        'src',
        'mold',
        'fixtures',
        'hooks',
        fileName,
      ),
    );
  }

  group('moldHookFileUriImport', () {
    test('emits a file URI import for the absolute hook path', () {
      final hookFile = File(p.join(hooksDirectory.path, MoldHooks.shape));
      final source = moldHookFileUriImport(
        hookFile: hookFile,
        asPrefix: '_foundry_mold_hook',
      );

      expect(
        source,
        "import '${hookFile.absolute.uri}' as _foundry_mold_hook;",
      );
    });
  });

  group('runMoldHookInProcess', () {
    test('is a no-op when hookFile is null', () async {
      final context = buildContext(values: const {'a': 1});

      await runMoldHookInProcess(
        phase: MoldHookPhase.prepare,
        hookFile: null,
        context: context,
        entryPoint: mutate_context.run,
      );

      expect(context.entries, {'a': 1});
    });

    test('is a no-op when the hook file does not exist', () async {
      final context = buildContext(values: const {'a': 1});
      final missingHook = File(
        p.join(hooksDirectory.path, 'does_not_exist.dart'),
      );

      await runMoldHookInProcess(
        phase: MoldHookPhase.prepare,
        hookFile: missingHook,
        context: context,
        entryPoint: mutate_context.run,
      );

      expect(context.entries, {'a': 1});
    });

    test('applies set, merge, and remove mutations from a fixture hook',
        () async {
      final hookFile = fixtureHook('mutate_context.dart');
      expect(hookFile.existsSync(), isTrue);
      final context = buildContext(values: const {'name': 'Ada'});

      await runMoldHookInProcess(
        phase: MoldHookPhase.prepare,
        hookFile: hookFile,
        context: context,
        entryPoint: mutate_context.run,
      );

      expect(context.contains('name'), isFalse);
      expect(context.requiredString('greeting'), 'hi Ada');
      expect(context.requiredBool('merged'), isTrue);
      expect(context.requiredInt('count'), 2);
    });

    test('preserves non-JSON object identity across the hook boundary',
        () async {
      final hookFile = fixtureHook('preserve_seeded_object.dart');
      final token = preserve_seeded_object.createSeedToken();
      final context = buildContext(values: {'seed': token});

      await runMoldHookInProcess(
        phase: MoldHookPhase.shape,
        hookFile: hookFile,
        context: context,
        entryPoint: preserve_seeded_object.run,
      );

      expect(identical(context.required<Object>('seen'), token), isTrue);
      expect(context.requiredString('seen_type'), token.runtimeType.toString());
    });

    test('runs the hook with the output directory as cwd', () async {
      final hookFile = fixtureHook('report_cwd.dart');
      final context = buildContext();

      await runMoldHookInProcess(
        phase: MoldHookPhase.finish,
        hookFile: hookFile,
        context: context,
        entryPoint: report_cwd.run,
      );

      final reportedCwd =
          Directory(context.requiredString('cwd')).resolveSymbolicLinksSync();
      expect(reportedCwd, outputDirectory.resolveSymbolicLinksSync());
      expect(
        Directory.current.resolveSymbolicLinksSync(),
        isNot(reportedCwd),
      );
    });

    test(
        'throws MoldHookException when the hook throws '
        'FoundryHookException', () async {
      final hookFile = fixtureHook('throw_foundry_hook_exception.dart');
      final context = buildContext();

      await expectLater(
        runMoldHookInProcess(
          phase: MoldHookPhase.shape,
          hookFile: hookFile,
          context: context,
          entryPoint: throw_foundry_hook_exception.run,
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

    test('throws MoldHookException when entryPoint is missing', () async {
      final hookFile = File(p.join(hooksDirectory.path, MoldHooks.finish))
        ..writeAsStringSync('// no run entry point\n');
      final context = buildContext();

      await expectLater(
        runMoldHookInProcess(
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
                contains('Missing required top-level function'),
              ),
        ),
      );
    });

    test('restores cwd when the hook throws', () async {
      final hookFile = fixtureHook('throw_foundry_hook_exception.dart');
      final context = buildContext();
      final cwdBefore = Directory.current.resolveSymbolicLinksSync();

      await expectLater(
        runMoldHookInProcess(
          phase: MoldHookPhase.shape,
          hookFile: hookFile,
          context: context,
          entryPoint: throw_foundry_hook_exception.run,
        ),
        throwsA(isA<MoldHookException>()),
      );

      expect(Directory.current.resolveSymbolicLinksSync(), cwdBefore);
    });
  });
}
