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

  group('inspectMold', () {
    test('reports a valid mold with no errors', () async {
      final report = await inspectMold(p.join(fixtures.path, 'valid_mold'));

      expect(report.isValid, isTrue);
      expect(report.mold, isNotNull);
      expect(report.mold!.name, 'demo_app');
      expect(
        report.issues.where((i) => i.severity == MoldIssueSeverity.error),
        isEmpty,
      );
    });

    test('propagates load issues when the mold fails to load', () async {
      final report = await inspectMold(p.join(fixtures.path, 'does_not_exist'));

      expect(report.isValid, isFalse);
      expect(report.mold, isNull);
      expect(report.issues, isNotEmpty);
      expect(report.issues.first.message, contains('does not exist'));
    });

    test('reports a missing template directory as an error', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_no_template_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await writeMoldPubspec(
        directory: tempDir,
        name: 'no_template',
        description: 'Mold without a template directory',
      );
      await File(p.join(tempDir.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

const moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
''');

      final report = await inspectMold(tempDir.path);

      expect(report.isValid, isFalse);
      expect(
        report.issues,
        contains(
          isA<MoldIssue>()
              .having((i) => i.severity, 'severity', MoldIssueSeverity.error)
              .having((i) => i.message, 'message', contains('template')),
        ),
      );
    });

    test('reports an empty variable group as a warning', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_empty_vars_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await writeMoldPubspec(
        directory: tempDir,
        name: 'empty_vars',
        description: 'Mold without variables',
      );
      await File(p.join(tempDir.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

const moldVariables = FoundryVariableGroup(variables: {});
''');
      await Directory(p.join(tempDir.path, 'template')).create();

      final report = await inspectMold(tempDir.path);

      expect(report.isValid, isTrue);
      expect(
        report.issues,
        contains(
          isA<MoldIssue>()
              .having(
                (i) => i.severity,
                'severity',
                MoldIssueSeverity.warning,
              )
              .having((i) => i.message, 'message', contains('variables')),
        ),
      );
    });

    test('reports present hook files as warnings', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('foundry_inspect_hooks_');
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
      await Directory(p.join(tempDir.path, 'template')).create();
      final hooksDir = Directory(p.join(tempDir.path, MoldHooks.directory));
      await hooksDir.create();
      await File(p.join(hooksDir.path, MoldHooks.shape)).writeAsString('//');

      final report = await inspectMold(tempDir.path);

      expect(report.isValid, isTrue);
      expect(
        report.issues,
        contains(
          isA<MoldIssue>()
              .having(
                (i) => i.severity,
                'severity',
                MoldIssueSeverity.warning,
              )
              .having((i) => i.path, 'path', endsWith(MoldHooks.shapePath))
              .having((i) => i.message, 'message', contains('shape')),
        ),
      );
    });
  });
}
