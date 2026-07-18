import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_test_support.dart';

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

    test('rejects missing pubspec.yaml', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_no_pubspec_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(
        () => loadMold(tempDir.path),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
      );
    });

    test('loads a valid mold directory', () async {
      final mold = await loadMold(p.join(fixtures.path, 'valid_mold'));

      expect(mold.name, 'demo_app');
      expect(mold.description, 'A minimal demo mold for tests');
      expect(mold.pubspec.version, '0.0.1');
      expect(mold.variableGroup.variables, hasLength(1));
      expect(
        mold.variableGroup.variables['project_name'],
        isA<FoundryStringVariable>(),
      );
      expect(mold.prepareHook, isNull);
      expect(mold.shapeHook, isNull);
      expect(mold.finishHook, isNull);
    });

    test('round-trips boolean, int, and double variables from a fixture',
        () async {
      final mold = await loadMold(p.join(fixtures.path, 'scalar_kinds_mold'));

      expect(mold.name, 'scalar_kinds');
      expect(mold.variableGroup.variables, hasLength(3));
      expect(
        mold.variableGroup.variables['use_null_safety'],
        isA<FoundryBooleanVariable>().having(
          (variable) => variable.label,
          'label',
          'Use null safety',
        ),
      );
      expect(
        mold.variableGroup.variables['port'],
        isA<FoundryIntVariable>().having(
          (variable) => variable.label,
          'label',
          'Port',
        ),
      );
      expect(
        mold.variableGroup.variables['scale'],
        isA<FoundryDoubleVariable>().having(
          (variable) => variable.label,
          'label',
          'Scale',
        ),
      );
    });

    test('round-trips single and multiple choice variables from a fixture',
        () async {
      final mold = await loadMold(p.join(fixtures.path, 'choice_kinds_mold'));

      expect(mold.name, 'choice_kinds');
      expect(mold.variableGroup.variables, hasLength(2));
      expect(
        mold.variableGroup.variables['project_type'],
        isA<FoundrySingleChoiceVariable<String>>()
            .having(
          (variable) => variable.label,
          'label',
          'Project type',
        )
            .having(
          (variable) => variable.options,
          'options',
          ['app', 'package'],
        ),
      );
      expect(
        mold.variableGroup.variables['platforms'],
        isA<FoundryMultipleChoiceVariable<String>>()
            .having(
          (variable) => variable.label,
          'label',
          'Platforms',
        )
            .having(
          (variable) => variable.options,
          'options',
          ['android', 'ios', 'web'],
        ),
      );
    });

    test('round-trips nested object variables from a fixture', () async {
      final mold = await loadMold(p.join(fixtures.path, 'object_kind_mold'));

      expect(mold.name, 'object_kind');
      expect(mold.variableGroup.variables, hasLength(1));
      final publish = mold.variableGroup.variables['publish'];
      expect(
        publish,
        isA<FoundryObjectVariable>().having(
          (variable) => variable.label,
          'label',
          'Publish settings',
        ),
      );

      final nested = (publish! as FoundryObjectVariable).group;
      expect(nested.variables, hasLength(3));
      expect(
        nested.variables['host'],
        isA<FoundryStringVariable>().having(
          (variable) => variable.label,
          'label',
          'Host',
        ),
      );
      expect(
        nested.variables['port'],
        isA<FoundryIntVariable>().having(
          (variable) => variable.label,
          'label',
          'Port',
        ),
      );
      expect(
        nested.variables['secure'],
        isA<FoundryBooleanVariable>().having(
          (variable) => variable.label,
          'label',
          'Secure',
        ),
      );
    });

    test('resolves standard hook files when present', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_with_hooks_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await writeMoldPubspec(
        directory: tempDir,
        name: 'hooked',
        description: 'Mold with hooks',
      );
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

    test('rejects invalid pubspec.yaml', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'invalid_pubspec')),
        throwsA(isA<MoldLoadException>()),
      );
    });

    test('rejects pubspec without foundry_core dependency', () async {
      expect(
        () => loadMold(p.join(fixtures.path, 'missing_foundry_core')),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('foundry_core'),
          ),
        ),
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

    test('rejects pubspec when dart pub get fails', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_bad_pub_get_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('''
name: broken
description: Broken mold dependencies
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: ./does_not_exist
''');
      await File(p.join(tempDir.path, 'variables.dart')).writeAsString('//');

      expect(
        () => loadMold(tempDir.path),
        throwsA(
          isA<MoldLoadException>().having(
            (error) => error.issues.first.message,
            'message',
            contains('pub get failed'),
          ),
        ),
      );
    });
  });
}
