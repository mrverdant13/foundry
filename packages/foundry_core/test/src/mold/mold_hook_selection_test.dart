import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory moldDirectory;

  setUp(() async {
    moldDirectory =
        await Directory.systemTemp.createTemp('foundry_hook_selection_');
  });

  tearDown(() async {
    if (moldDirectory.existsSync()) {
      await moldDirectory.delete(recursive: true);
    }
  });

  Mold buildMold() {
    return Mold(
      directory: moldDirectory,
      pubspec: const MoldPubspec(
        name: 'hook_selection_demo',
        description: 'Mold used to exercise hook selection validation',
        version: '0.0.1',
      ),
      variableGroup: const FoundryVariableGroup(variables: {}),
    );
  }

  Future<void> touchHook(String relativePath) async {
    final file = File(p.join(moldDirectory.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString('// placeholder\n');
  }

  group('moldHookPathForPhase', () {
    test('maps each phase to its relative hook path', () {
      expect(
        moldHookPathForPhase(MoldHookPhase.prepare),
        MoldHooks.preparePath,
      );
      expect(moldHookPathForPhase(MoldHookPhase.shape), MoldHooks.shapePath);
      expect(moldHookPathForPhase(MoldHookPhase.finish), MoldHooks.finishPath);
    });
  });

  group('validateMoldHookSelection', () {
    test('accepts empty skip and required sets', () {
      expect(
        () => validateMoldHookSelection(mold: buildMold()),
        returnsNormally,
      );
    });

    test('allows skipping phases that are not required', () async {
      await touchHook(MoldHooks.preparePath);
      expect(
        () => validateMoldHookSelection(
          mold: buildMold(),
          skipHooks: {MoldHookPhase.prepare, MoldHookPhase.shape},
        ),
        returnsNormally,
      );
    });

    test('allows required phases when their hook files exist', () async {
      await touchHook(MoldHooks.preparePath);
      await touchHook(MoldHooks.finishPath);
      expect(
        () => validateMoldHookSelection(
          mold: buildMold(),
          requiredHooks: {MoldHookPhase.prepare, MoldHookPhase.finish},
        ),
        returnsNormally,
      );
    });

    test('fails when a required phase is also skipped', () {
      expect(
        () => validateMoldHookSelection(
          mold: buildMold(),
          skipHooks: {MoldHookPhase.shape, MoldHookPhase.finish},
          requiredHooks: {MoldHookPhase.shape},
        ),
        throwsA(
          isA<MoldHookSelectionException>().having(
            (e) => e.skippedRequiredPhases,
            'skippedRequiredPhases',
            {MoldHookPhase.shape},
          ).having(
            (e) => e.message,
            'message',
            contains('Cannot skip required hook phase(s): shape'),
          ),
        ),
      );
    });

    test('fails when a required hook file is missing', () {
      expect(
        () => validateMoldHookSelection(
          mold: buildMold(),
          requiredHooks: {MoldHookPhase.finish},
        ),
        throwsA(
          isA<MoldHookSelectionException>().having(
            (e) => e.missingRequiredPhases,
            'missingRequiredPhases',
            {MoldHookPhase.finish},
          ).having(
            (e) => e.message,
            'message',
            contains(
              'Required hook file(s) missing: ${MoldHooks.finishPath}',
            ),
          ),
        ),
      );
    });

    test('reports skipped required phases before missing files', () {
      expect(
        () => validateMoldHookSelection(
          mold: buildMold(),
          skipHooks: {MoldHookPhase.prepare},
          requiredHooks: {MoldHookPhase.prepare, MoldHookPhase.finish},
        ),
        throwsA(
          isA<MoldHookSelectionException>().having(
            (e) => e.skippedRequiredPhases,
            'skippedRequiredPhases',
            {MoldHookPhase.prepare},
          ).having(
            (e) => e.missingRequiredPhases,
            'missingRequiredPhases',
            isEmpty,
          ),
        ),
      );
    });

    test('Mold.policyFile is present only when hooks/policy.dart exists',
        () async {
      final mold = buildMold();
      expect(mold.policyFile, isNull);

      await touchHook(MoldHooks.policyPath);
      expect(mold.policyFile, isNotNull);
      expect(mold.policyFile!.path, endsWith(MoldHooks.policyPath));
    });
  });

  group('MoldHookSelectionException', () {
    test('toString includes the message', () {
      const exception = MoldHookSelectionException(
        message: 'Cannot skip required hook phase(s): prepare',
        skippedRequiredPhases: {MoldHookPhase.prepare},
      );
      expect(
        exception.toString(),
        'MoldHookSelectionException: '
        'Cannot skip required hook phase(s): prepare',
      );
    });
  });
}
