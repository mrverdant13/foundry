import 'dart:io';

import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'commands/mold/mold_command_test_support.dart';

void main() {
  late Directory moldDirectory;
  late Directory outputDirectory;
  late Directory helperParent;

  setUp(() async {
    moldDirectory = await Directory.systemTemp.createTemp(
      'foundry_session_launch_mold_',
    );
    outputDirectory = await Directory.systemTemp.createTemp(
      'foundry_session_launch_out_',
    );
    helperParent = await Directory.systemTemp.createTemp(
      'foundry_session_launch_helpers_',
    );
  });

  tearDown(() async {
    for (final directory in [moldDirectory, outputDirectory, helperParent]) {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });

  Future<Directory> resolveFoundryCliRoot() {
    return resolvePackageRoot('foundry_cli');
  }

  group('launchBatchMoldCastSession', () {
    test('fails clearly when the mold directory is missing', () async {
      final result = await launchBatchMoldCastSession(
        moldPath: p.join(moldDirectory.path, 'missing'),
        outputPath: outputDirectory.path,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.message, contains('does not exist'));
      expect(helperParent.listSync(), isEmpty);
    });

    test('fails clearly when variables.dart is missing', () async {
      await File(p.join(moldDirectory.path, 'pubspec.yaml')).writeAsString('''
name: missing_vars_mold
description: Missing variables
version: 0.0.1
publish_to: none
environment:
  sdk: ">=3.5.0 <4.0.0"
dependencies:
  foundry_core:
    path: ${foundryCorePackageRoot().path}
''');

      final result = await launchBatchMoldCastSession(
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.message, contains('variables.dart'));
      expect(helperParent.listSync(), isEmpty);
    });

    test(
      'launches a helper session with live visibleWhen and defaultValue',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final cliRoot = await resolveFoundryCliRoot();
        final coreRoot = foundryCorePackageRoot();

        final packageResult = await launchBatchMoldCastSession(
          moldPath: moldDirectory.path,
          outputPath: p.join(outputDirectory.path, 'package'),
          varsFlag: 'project_type=package,project_name=LiveDemo',
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
        );

        expect(packageResult, isA<MoldCastSessionLaunchSuccess>());
        final packageSuccess = packageResult as MoldCastSessionLaunchSuccess;
        expect(packageSuccess.artifactCount, 1);
        expect(packageSuccess.vars['project_type'], 'package');
        expect(packageSuccess.vars['package_name'], 'livedemo');
        expect(
          await File(
            p.join(outputDirectory.path, 'package', 'README.md'),
          ).readAsString(),
          'type=package\n'
          'name=LiveDemo\n'
          'package=livedemo\n'
          'shaped=yes\n',
        );
        expect(
          helperParent.listSync(),
          isEmpty,
          reason: 'helper dirs must be removed after success',
        );

        final appOut = p.join(outputDirectory.path, 'app');
        final appResult = await launchBatchMoldCastSession(
          moldPath: moldDirectory.path,
          outputPath: appOut,
          varsFlag: 'project_type=app,project_name=LiveDemo',
          force: true,
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
        );

        expect(appResult, isA<MoldCastSessionLaunchSuccess>());
        final appSuccess = appResult as MoldCastSessionLaunchSuccess;
        expect(appSuccess.vars['project_type'], 'app');
        expect(appSuccess.vars.containsKey('package_name'), isFalse);
        expect(
          await File(p.join(appOut, 'README.md')).readAsString(),
          'type=app\n'
          'name=LiveDemo\n'
          'shaped=yes\n',
        );
        expect(
          helperParent.listSync(),
          isEmpty,
          reason: 'helper dirs must be removed after second success',
        );
      },
    );

    test('removes the helper directory when the session fails', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        varsFlag: 'not_a_real_key=1',
        tempParent: helperParent,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'parse');
      expect(failure.message, contains('not_a_real_key'));
      expect(
        helperParent.listSync(),
        isEmpty,
        reason: 'helper dirs must be removed after failure',
      );
    });

    test('keepHelperForDebug retains the helper for inspection', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        varsFlag: 'project_type=app,project_name=KeepHelper',
        tempParent: helperParent,
        keepHelperForDebug: true,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
      );

      expect(result, isA<MoldCastSessionLaunchSuccess>());
      final helpers = helperParent.listSync().whereType<Directory>().toList();
      expect(helpers, hasLength(1));
      final helper = helpers.single;
      final pubspec = await File(
        p.join(helper.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('name: $moldCastSessionHelperPackageName'));
      expect(pubspec, contains('foundry_cli:'));
      expect(pubspec, contains('path:'));
      expect(pubspec, contains(moldDirectory.absolute.path));
      expect(
        File(p.join(helper.path, 'pubspec_overrides.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(helper.path, '.dart_tool', 'package_config.json'),
        ).existsSync(),
        isTrue,
      );
      expect(
        await File(
          p.join(helper.path, moldCastSessionHelperEntrypointRelativePath),
        ).readAsString(),
        contains('as mold_variables;'),
      );
    });
  });

  test('resolveFoundryCliHelperDependency uses a path dep in this workspace',
      () async {
    final dependency = await resolveFoundryCliHelperDependency();
    expect(dependency, isA<FoundryCliPathDependency>());
    final pathDependency = dependency as FoundryCliPathDependency;
    expect(
      File(p.join(pathDependency.packageRoot, 'pubspec.yaml')).existsSync(),
      isTrue,
    );
    expect(
      await File(
        p.join(pathDependency.packageRoot, 'pubspec.yaml'),
      ).readAsString(),
      contains('name: foundry_cli'),
    );
  });
}

Future<void> _writeLiveCallbackMold(Directory directory) async {
  final corePath = foundryCorePackageRoot().absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: live_callback_mold
description: Mold whose callbacks must stay live in the session helper
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: $corePath
''');

  await File(p.join(directory.path, 'variables.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: {'app', 'package'},
      displayLabel: (value) => value,
    ),
    'project_name': FoundryStringVariable(label: 'Project name'),
    'package_name': FoundryStringVariable(
      label: 'Package name',
      visibleWhen: (context) =>
          context.requiredString('project_type') == 'package',
      defaultValue: (context) =>
          (context.optionalString('project_name') ?? '').toLowerCase(),
    ),
  },
);
''');

  final templateDir = Directory(p.join(directory.path, 'template'))
    ..createSync();
  await File(p.join(templateDir.path, 'README.md')).writeAsString(
    'type={{ project_type }}\n'
    'name={{ project_name }}\n'
    '{% if package_name %}package={{ package_name }}\n'
    '{% endif %}shaped={{ shaped }}\n',
  );

  final hooksDir = Directory(p.join(directory.path, 'hooks'))..createSync();
  await File(p.join(hooksDir.path, 'shape.dart')).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('shaped', 'yes');
}
''');
}
