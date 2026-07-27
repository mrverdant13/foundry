import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:test/test.dart';

void main() {
  group('buildMoldCastSessionHelperPubspec', () {
    test('uses path dependency for foundry_cli in monorepo mode', () {
      final pubspec = buildMoldCastSessionHelperPubspec(
        moldPackageName: 'demo_mold',
        moldPath: '/tmp/demo_mold',
        foundryCli: const FoundryCliPathDependency(
          '/repo/packages/foundry_cli',
        ),
      );

      expect(pubspec, contains('name: $moldCastSessionHelperPackageName'));
      expect(
        pubspec,
        contains(
          '  foundry_cli:\n'
          '    path: "/repo/packages/foundry_cli"',
        ),
      );
      expect(
        pubspec,
        contains(
          '  demo_mold:\n'
          '    path: "/tmp/demo_mold"',
        ),
      );
      expect(pubspec, isNot(contains('version:')));
    });

    test('uses hosted version when foundry_cli is installed from pub', () {
      final pubspec = buildMoldCastSessionHelperPubspec(
        moldPackageName: 'demo_mold',
        moldPath: '/tmp/demo_mold',
        foundryCli: const FoundryCliHostedDependency('0.0.1-dev.1'),
      );

      expect(
        pubspec,
        contains(
          '  foundry_cli:\n'
          '    version: "0.0.1-dev.1"',
        ),
      );
      expect(pubspec, isNot(contains('path: "/repo')));
    });

    test('yaml-quotes paths that contain spaces', () {
      final pubspec = buildMoldCastSessionHelperPubspec(
        moldPackageName: 'spaced_mold',
        moldPath: '/tmp/my mold',
        foundryCli: const FoundryCliPathDependency('/repo/foundry cli'),
      );

      expect(pubspec, contains('path: "/tmp/my mold"'));
      expect(pubspec, contains('path: "/repo/foundry cli"'));
    });
  });

  group('buildMoldCastSessionHelperPubspecOverrides', () {
    test('returns null when no foundry_core override is needed', () {
      expect(
        buildMoldCastSessionHelperPubspecOverrides(),
        isNull,
      );
    });

    test('writes a foundry_core path override', () {
      final overrides = buildMoldCastSessionHelperPubspecOverrides(
        foundryCoreOverridePath: '/repo/packages/foundry_core',
      );

      expect(
        overrides,
        'dependency_overrides:\n'
        '  foundry_core:\n'
        '    path: "/repo/packages/foundry_core"\n',
      );
    });
  });

  group('buildMoldCastSessionBridgeSource', () {
    test('imports variables.dart by file URI and runs CastSession', () {
      final source = buildMoldCastSessionBridgeSource(
        variablesUri: Uri.file('/tmp/mold/variables.dart'),
        hooks: const MoldCastSessionHelperHookImports(),
      );

      expect(
        source,
        contains(
          "import 'file:///tmp/mold/variables.dart' as mold_variables;",
        ),
      );
      expect(source, contains('variableGroup: mold_variables.moldVariables'));
      expect(source, contains('CastSession('));
      expect(source, contains('.runBatch('));
      expect(source, contains('.runInteractive('));
      expect(source, contains('.runSeeded('));
      expect(source, contains('.runFinishOnly('));
      expect(source, contains('describeMoldVariableGroup'));
      expect(source, contains('hasBatchInputs'));
      expect(source, contains('seededValues'));
      expect(source, contains('finishOnly'));
      expect(source, contains('describeOnly'));
      expect(source, contains("'describe': true"));
      expect(source, contains("kind: 'cancel'"));
      expect(source, contains('const CastSessionHooks()'));
      expect(source, isNot(contains('prepare_hook')));
      expect(source, isNot(contains('shape_hook')));
      expect(source, isNot(contains('finish_hook')));
    });

    test('imports present hook files and wires CastSessionHooks', () {
      final source = buildMoldCastSessionBridgeSource(
        variablesUri: Uri.file('/tmp/mold/variables.dart'),
        hooks: MoldCastSessionHelperHookImports(
          prepareUri: Uri.file('/tmp/mold/hooks/prepare.dart'),
          shapeUri: Uri.file('/tmp/mold/hooks/shape.dart'),
          finishUri: Uri.file('/tmp/mold/hooks/finish.dart'),
        ),
      );

      expect(
        source,
        contains(
          "import 'file:///tmp/mold/hooks/prepare.dart' as prepare_hook;",
        ),
      );
      expect(
        source,
        contains(
          "import 'file:///tmp/mold/hooks/shape.dart' as shape_hook;",
        ),
      );
      expect(
        source,
        contains(
          "import 'file:///tmp/mold/hooks/finish.dart' as finish_hook;",
        ),
      );
      expect(source, contains('prepare: prepare_hook.run,'));
      expect(source, contains('shape: shape_hook.run,'));
      expect(source, contains('finish: finish_hook.run,'));
      expect(source, isNot(contains('const CastSessionHooks()')));
    });
  });
}
