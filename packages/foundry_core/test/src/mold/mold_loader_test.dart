import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _fixtureRoot() {
  var current = Directory.current;
  while (true) {
    final fixture =
        Directory(p.join(current.path, 'test', 'fixtures', 'valid_mold'));
    if (fixture.existsSync()) {
      return Directory(p.join(current.path, 'test', 'fixtures'));
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      fail('Could not locate test/fixtures from ${Directory.current.path}');
    }
    current = parent;
  }
}

void main() {
  late Directory fixtures;

  setUp(() {
    fixtures = _fixtureRoot();
  });

  group('loadMold', () {
    test('rejects a missing mold directory', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'does_not_exist')),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('rejects missing mold.yaml', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_no_manifest_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(
        () => loadMold(tempDir.path),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('mold.yaml'),
          ),
        ),
      );
    });

    test('loads a valid mold directory', () async {
      final mold = await loadMold(p.join(fixtures.path, 'valid_mold'));

      expect(mold.name, 'demo_app');
      expect(mold.description, 'A minimal demo mold for tests');
      expect(mold.variableGroup.variables, hasLength(1));
      expect(
        mold.variableGroup.variables['project_name'],
        isA<FoundryStringVariable>(),
      );
      expect(mold.prepareHook, isNull);
      expect(mold.shapeHook, isNull);
      expect(mold.finishHook, isNull);
    });

    test('resolves standard hook files when present', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_with_hooks_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await File(p.join(tempDir.path, 'mold.yaml')).writeAsString('''
name: hooked
description: Mold with hooks
''');
      await File(p.join(tempDir.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

const moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''');
      final hooksDir = Directory(p.join(tempDir.path, MoldHooks.directory));
      await hooksDir.create();
      await File(p.join(hooksDir.path, MoldHooks.prepare)).writeAsString('//');
      await File(p.join(hooksDir.path, MoldHooks.finish)).writeAsString('//');

      final mold = await loadMold(tempDir.path);

      expect(mold.prepareHook?.path, endsWith(MoldHooks.preparePath));
      expect(mold.shapeHook, isNull);
      expect(mold.finishHook?.path, endsWith(MoldHooks.finishPath));
    });

    test('rejects missing variables.dart', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'missing_variables')),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('variables.dart'),
          ),
        ),
      );
    });

    test('rejects invalid mold.yaml', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'invalid_manifest')),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('rejects missing moldVariables symbol', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'missing_mold_variables')),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('moldVariables'),
          ),
        ),
      );
    });

    test('rejects moldVariables with the wrong type', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'wrong_mold_variables_type')),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('FoundryVariableGroup'),
          ),
        ),
      );
    });
  });
}
