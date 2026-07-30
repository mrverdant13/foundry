import 'dart:convert';
import 'dart:io';

import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/mold_cast_session_helper_cache.dart';
import 'package:foundry_cli/src/mold_cast_session_launcher.dart';
import 'package:foundry_cli/src/tui/gather_cast_variables.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:foundry_core/foundry_core.dart';
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
        cacheHelperResolve: false,
        moldPath: p.join(moldDirectory.path, 'missing'),
        outputPath: outputDirectory.path,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      expect(result.isSuccess, isFalse);
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.message, contains('does not exist'));
      expect(
        '$failure',
        contains('MoldCastSessionLaunchFailure(load:'),
      );
      expect(helperParent.listSync(), isEmpty);
    });

    test('fails clearly when pubspec.yaml is missing', () async {
      await File(p.join(moldDirectory.path, 'variables.dart')).writeAsString(
        'final moldVariables = null;\n',
      );

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.message, contains('pubspec.yaml'));
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
        cacheHelperResolve: false,
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

    test('fails clearly when pubspec.yaml is invalid', () async {
      await File(p.join(moldDirectory.path, 'pubspec.yaml')).writeAsString(
        'name: [\n',
      );
      await File(p.join(moldDirectory.path, 'variables.dart')).writeAsString(
        'final moldVariables = null;\n',
      );

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.exitCode, FoundryExitCode.userError.code);
    });

    test(
      'launches a helper session with live visibleWhen and defaultValue',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final cliRoot = await resolveFoundryCliRoot();
        final coreRoot = foundryCorePackageRoot();

        final packageResult = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: p.join(outputDirectory.path, 'package'),
          varsFlag: 'project_type=package,project_name=LiveDemo',
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
        );

        expect(packageResult, isA<MoldCastSessionLaunchSuccess>());
        expect(packageResult.isSuccess, isTrue);
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
          cacheHelperResolve: false,
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

    test(
      'resolves foundry_cli/core automatically for path dependencies',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          varsFileValues: const {
            'project_type': 'package',
            'project_name': 'AutoResolve',
          },
          skipHooks: MoldHookPhase.values.toSet(),
          tempParent: helperParent,
          keepHelperForDebug: true,
        );

        expect(result, isA<MoldCastSessionLaunchSuccess>());
        final helpers = helperParent.listSync().whereType<Directory>().toList();
        expect(helpers, hasLength(1));
        expect(
          File(p.join(helpers.single.path, 'pubspec_overrides.yaml'))
              .existsSync(),
          isTrue,
        );
        final request = Map<String, Object?>.from(
          jsonDecode(
            await File(p.join(helpers.single.path, 'request.json'))
                .readAsString(),
          ) as Map<dynamic, dynamic>,
        );
        expect(request['skipHooks'], equals(['prepare', 'shape', 'finish']));
        expect(request['varsFileValues'], isA<Map<dynamic, dynamic>>());
      },
    );

    test(
      'omits foundry_core overrides for hosted foundry_cli dependencies',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          varsFlag: 'project_type=app,project_name=Hosted',
          tempParent: helperParent,
          keepHelperForDebug: true,
          foundryCliDependency: const FoundryCliHostedDependency(
            foundryCliVersion,
          ),
          pubGetRunner: (helperRoot) async {
            expect(
              File(p.join(helperRoot.path, 'pubspec_overrides.yaml'))
                  .existsSync(),
              isFalse,
            );
            return ProcessResult(1, 0, '', '');
          },
          childRunner: ({
            required helperRoot,
            required entrypoint,
            required requestFile,
            environment,
          }) async {
            final request = Map<String, Object?>.from(
              jsonDecode(await requestFile.readAsString())
                  as Map<dynamic, dynamic>,
            );
            final resultPath = request['resultPath']! as String;
            await File(resultPath).writeAsString(
              jsonEncode({
                'ok': true,
                'artifactCount': 0,
                'vars': <String, Object?>{},
                'writtenFiles': <String>[],
                'outputDirectory': outputDirectory.path,
              }),
            );
            return 0;
          },
        );

        expect(result, isA<MoldCastSessionLaunchSuccess>());
      },
    );

    test('uses the system temp directory when tempParent is omitted', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
        pubGetRunner: (_) async => ProcessResult(1, 1, '', 'boom'),
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      expect((result as MoldCastSessionLaunchFailure).kind, 'resolve');
    });

    test('reports resolve failures with pub get output', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
        pubGetRunner: (_) async => ProcessResult(1, 1, 'out', 'err'),
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'resolve');
      expect(failure.message, contains('dart pub get failed: outerr'));
      expect(helperParent.listSync(), isEmpty);
    });

    test('reports resolve failures when pub get output is empty', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
        pubGetRunner: (_) async => ProcessResult(1, 1, '', ''),
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'resolve');
      expect(
        failure.message,
        'dart pub get failed for the mold cast session helper.',
      );
    });

    test('fails when the child exits without a result payload', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final zeroExit = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
        pubGetRunner: (_) async => ProcessResult(1, 0, '', ''),
        childRunner: ({
          required helperRoot,
          required entrypoint,
          required requestFile,
          environment,
        }) async =>
            0,
      );
      expect(zeroExit, isA<MoldCastSessionLaunchFailure>());
      final zeroFailure = zeroExit as MoldCastSessionLaunchFailure;
      expect(zeroFailure.kind, 'internal');
      expect(zeroFailure.exitCode, FoundryExitCode.internalError.code);
      expect(zeroFailure.message, contains('exit code 0'));

      final nonzeroExit = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        tempParent: helperParent,
        foundryCliDependency: FoundryCliPathDependency(
          (await resolveFoundryCliRoot()).path,
        ),
        foundryCoreOverridePath: foundryCorePackageRoot().path,
        pubGetRunner: (_) async => ProcessResult(1, 0, '', ''),
        childRunner: ({
          required helperRoot,
          required entrypoint,
          required requestFile,
          environment,
        }) async =>
            7,
      );
      expect(nonzeroExit, isA<MoldCastSessionLaunchFailure>());
      final nonzeroFailure = nonzeroExit as MoldCastSessionLaunchFailure;
      expect(nonzeroFailure.kind, 'internal');
      expect(nonzeroFailure.exitCode, 7);
    });

    test('removes the helper directory when the session fails', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
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

    test(
      'runs interactive gather via FOUNDRY_E2E_VARS without batch flags',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(
            (await resolveFoundryCliRoot()).path,
          ),
          foundryCoreOverridePath: foundryCorePackageRoot().path,
          environment: {
            foundryE2eVarsEnvironmentKey: jsonEncode({
              'project_type': 'package',
              'project_name': 'LiveInteractive',
            }),
          },
        );

        expect(result, isA<MoldCastSessionLaunchSuccess>());
        final success = result as MoldCastSessionLaunchSuccess;
        expect(success.vars['project_type'], 'package');
        expect(success.vars['project_name'], 'LiveInteractive');
        expect(success.vars['package_name'], 'liveinteractive');
        expect(
          await File(
            p.join(outputDirectory.path, 'README.md'),
          ).readAsString(),
          'type=package\n'
          'name=LiveInteractive\n'
          'package=liveinteractive\n'
          'shaped=yes\n',
        );
        expect(helperParent.listSync(), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('keepHelperForDebug retains the helper for inspection', () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
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
      // Paths are YAML-embedded via jsonEncode, so Windows backslashes are
      // escaped in the file (e.g. C:\\Users\\...) rather than raw absolute.path.
      expect(pubspec, contains(jsonEncode(moldDirectory.absolute.path)));
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

    test(
      'launches a seeded session that keeps non-variable prepare seeds',
      () async {
        await _writeLiveCallbackMold(moldDirectory);
        await File(
          p.join(moldDirectory.path, 'hooks', 'prepare.dart'),
        ).writeAsString('''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
        await File(p.join(moldDirectory.path, 'template', 'README.md'))
            .writeAsString(
          'type={{ project_type }}\n'
          'name={{ project_name }}\n'
          '{% if package_name %}package={{ package_name }}\n'
          '{% endif %}shaped={{ shaped }}\n'
          'seed={{ seed }}\n',
        );

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          seededValues: const {
            'project_type': 'package',
            'project_name': 'RecastMe',
            'seed': 'stale',
            'shaped': 'stale',
          },
          force: true,
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(
            (await resolveFoundryCliRoot()).path,
          ),
          foundryCoreOverridePath: foundryCorePackageRoot().path,
        );

        expect(result, isA<MoldCastSessionLaunchSuccess>());
        final success = result as MoldCastSessionLaunchSuccess;
        expect(success.vars['package_name'], 'recastme');
        expect(success.vars['seed'], 'from-prepare');
        expect(success.vars['shaped'], 'yes');
        expect(
          await File(
            p.join(outputDirectory.path, 'README.md'),
          ).readAsString(),
          'type=package\n'
          'name=RecastMe\n'
          'package=recastme\n'
          'shaped=yes\n'
          'seed=from-prepare\n',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('rejects finishOnly without varsFileValues before resolving',
        () async {
      await _writeLiveCallbackMold(moldDirectory);

      final result = await launchBatchMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        finishOnly: true,
        tempParent: helperParent,
        pubGetRunner: (_) async {
          fail('pub get should not run when finishOnly lacks vars');
        },
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'internal');
      expect(failure.message, contains('varsFileValues'));
      expect(helperParent.listSync(), isEmpty);
    });

    test(
      'rejects seededValues combined with batch vars inputs before resolving',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final withFlag = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          seededValues: const {'project_name': 'Ada'},
          varsFlag: 'project_name=Ada',
          tempParent: helperParent,
          pubGetRunner: (_) async {
            fail('pub get should not run when seededValues conflict');
          },
        );
        expect(withFlag, isA<MoldCastSessionLaunchFailure>());
        final flagFailure = withFlag as MoldCastSessionLaunchFailure;
        expect(flagFailure.kind, 'internal');
        expect(flagFailure.message, contains('seededValues'));
        expect(flagFailure.message, contains('varsFlag'));

        final withFile = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          seededValues: const {'project_name': 'Ada'},
          varsFileValues: const {'project_name': 'Ada'},
          tempParent: helperParent,
          pubGetRunner: (_) async {
            fail('pub get should not run when seededValues conflict');
          },
        );
        expect(withFile, isA<MoldCastSessionLaunchFailure>());
        final fileFailure = withFile as MoldCastSessionLaunchFailure;
        expect(fileFailure.kind, 'internal');
        expect(fileFailure.message, contains('varsFileValues'));
        expect(helperParent.listSync(), isEmpty);
      },
    );

    test(
      'launches a finish-only session without re-rendering templates',
      () async {
        await _writeLiveCallbackMold(moldDirectory);
        await File(
          p.join(moldDirectory.path, 'hooks', 'finish.dart'),
        ).writeAsString(r'''
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  await File('finish_marker.txt').writeAsString(
    'name=${context.optionalString("project_name")}',
  );
}
''');
        final stale = File(p.join(outputDirectory.path, 'README.md'));
        await stale.writeAsString('# stale template output\n');

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          finishOnly: true,
          varsFileValues: const {
            'project_type': 'package',
            'project_name': 'FinishMe',
          },
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(
            (await resolveFoundryCliRoot()).path,
          ),
          foundryCoreOverridePath: foundryCorePackageRoot().path,
        );

        expect(result, isA<MoldCastSessionLaunchSuccess>());
        final success = result as MoldCastSessionLaunchSuccess;
        expect(success.artifactCount, 0);
        expect(success.writtenFilePaths, isEmpty);
        expect(success.vars['project_name'], 'FinishMe');
        expect(await stale.readAsString(), '# stale template output\n');
        expect(
          await File(
            p.join(outputDirectory.path, 'finish_marker.txt'),
          ).readAsString(),
          'name=FinishMe',
        );
        expect(helperParent.listSync(), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'reports missing finish hook from a finish-only session',
      () async {
        await _writeLiveCallbackMold(moldDirectory);

        final result = await launchBatchMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          finishOnly: true,
          varsFileValues: const {
            'project_type': 'app',
            'project_name': 'NoFinish',
          },
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(
            (await resolveFoundryCliRoot()).path,
          ),
          foundryCoreOverridePath: foundryCorePackageRoot().path,
        );

        expect(result, isA<MoldCastSessionLaunchFailure>());
        final failure = result as MoldCastSessionLaunchFailure;
        expect(failure.kind, 'hook');
        expect(failure.message, contains('No finish hook defined'));
        expect(failure.message, contains(MoldHooks.finishPath));
        expect(helperParent.listSync(), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('launchDescribeMoldCastSession', () {
    test(
      'reports live help, placeholder, '
      'and choice labels without writing output',
      () async {
        await _writeDescribeMetadataMold(moldDirectory);
        final marker = File(p.join(outputDirectory.path, 'should_not_exist'));

        final result = await launchDescribeMoldCastSession(
          cacheHelperResolve: false,
          moldPath: moldDirectory.path,
          tempParent: helperParent,
          foundryCliDependency: FoundryCliPathDependency(
            (await resolveFoundryCliRoot()).path,
          ),
          foundryCoreOverridePath: foundryCorePackageRoot().path,
        );

        expect(result, isA<MoldCastSessionDescribeSuccess>());
        final success = result as MoldCastSessionDescribeSuccess;
        expect(success.isSuccess, isTrue);

        final projectName = success.variables.singleWhere(
          (entry) => entry.key == 'project_name',
        );
        expect(projectName.description, 'UNIQUE_DESC_PROJECT_NAME');
        expect(projectName.help, 'UNIQUE_HELP_PROJECT_NAME');
        expect(projectName.placeholder, 'UNIQUE_PLACEHOLDER');

        final projectType = success.variables.singleWhere(
          (entry) => entry.key == 'project_type',
        );
        expect(
          projectType.options.map((option) => option.label),
          ['LABEL_app', 'LABEL_package'],
        );

        expect(marker.existsSync(), isFalse);
        expect(outputDirectory.listSync(), isEmpty);
        expect(
          helperParent.listSync(),
          isEmpty,
          reason: 'helper dirs must be removed after describe',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

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

      final result = await launchDescribeMoldCastSession(
        cacheHelperResolve: false,
        moldPath: moldDirectory.path,
        tempParent: helperParent,
      );

      expect(result, isA<MoldCastSessionLaunchFailure>());
      final failure = result as MoldCastSessionLaunchFailure;
      expect(failure.kind, 'load');
      expect(failure.message, contains('variables.dart'));
      expect(helperParent.listSync(), isEmpty);
    });
  });

  group('launchBatchMoldCastSession helper resolve cache', () {
    late Directory cacheRoot;
    late List<String> cacheEvents;
    var pubGetCount = 0;

    setUp(() async {
      cacheRoot = await Directory.systemTemp.createTemp(
        'foundry_session_launch_cache_',
      );
      cacheEvents = <String>[];
      pubGetCount = 0;
    });

    tearDown(() async {
      if (cacheRoot.existsSync()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    MoldCastSessionPubGetRunner countingPubGet({
      int exitCode = 0,
    }) {
      return (helperRoot) async {
        pubGetCount += 1;
        await Directory(p.join(helperRoot.path, '.dart_tool')).create(
          recursive: true,
        );
        await File(
          p.join(helperRoot.path, '.dart_tool', 'package_config.json'),
        ).writeAsString('{"configVersion":2,"packages":[]}');
        return ProcessResult(1, exitCode, '', exitCode == 0 ? '' : 'err');
      };
    }

    MoldCastSessionChildRunner successChild() {
      return ({
        required helperRoot,
        required entrypoint,
        required requestFile,
        environment,
      }) async {
        final request = Map<String, Object?>.from(
          jsonDecode(await requestFile.readAsString()) as Map<dynamic, dynamic>,
        );
        final resultPath = request['resultPath']! as String;
        await File(resultPath).writeAsString(
          jsonEncode({
            'ok': true,
            'artifactCount': 0,
            'vars': <String, Object?>{'project_name': 'CacheDemo'},
            'writtenFiles': <String>[],
            'outputDirectory': outputDirectory.path,
          }),
        );
        return 0;
      };
    }

    test('second launch reuses resolve when the cache key matches', () async {
      await _writeLiveCallbackMold(moldDirectory);
      final cliRoot = await resolveFoundryCliRoot();
      final coreRoot = foundryCorePackageRoot();

      Future<MoldCastSessionLaunchResult> launchOnce() {
        return launchBatchMoldCastSession(
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          varsFlag: 'project_type=app,project_name=CacheDemo',
          force: true,
          helperCacheRoot: cacheRoot,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
          pubGetRunner: countingPubGet(),
          childRunner: successChild(),
          onHelperCacheEvent: cacheEvents.add,
        );
      }

      final first = await launchOnce();
      expect(first, isA<MoldCastSessionLaunchSuccess>());
      expect(pubGetCount, 1);
      expect(cacheEvents, ['miss']);

      cacheEvents.clear();
      final second = await launchOnce();
      expect(second, isA<MoldCastSessionLaunchSuccess>());
      expect(pubGetCount, 1, reason: 'second launch must skip pub get');
      expect(cacheEvents, ['hit']);
      expect(cacheRoot.listSync().whereType<Directory>(), isNotEmpty);
    });

    test('editing mold pubspec.yaml invalidates the cache entry', () async {
      await _writeLiveCallbackMold(moldDirectory);
      final cliRoot = await resolveFoundryCliRoot();
      final coreRoot = foundryCorePackageRoot();

      Future<MoldCastSessionLaunchResult> launchOnce() {
        return launchBatchMoldCastSession(
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          varsFlag: 'project_type=app,project_name=CacheDemo',
          force: true,
          helperCacheRoot: cacheRoot,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
          pubGetRunner: countingPubGet(),
          childRunner: successChild(),
          onHelperCacheEvent: cacheEvents.add,
        );
      }

      expect(await launchOnce(), isA<MoldCastSessionLaunchSuccess>());
      expect(pubGetCount, 1);

      final pubspec = File(p.join(moldDirectory.path, 'pubspec.yaml'));
      await pubspec.writeAsString(
        '${await pubspec.readAsString()}\n# cache-bust\n',
      );

      cacheEvents.clear();
      expect(await launchOnce(), isA<MoldCastSessionLaunchSuccess>());
      expect(pubGetCount, 2);
      expect(cacheEvents, ['miss']);
    });

    test('failed resolves do not leave a successful cache stamp', () async {
      await _writeLiveCallbackMold(moldDirectory);
      final cliRoot = await resolveFoundryCliRoot();
      final coreRoot = foundryCorePackageRoot();

      final failed = await launchBatchMoldCastSession(
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        varsFlag: 'project_type=app,project_name=CacheDemo',
        helperCacheRoot: cacheRoot,
        foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
        foundryCoreOverridePath: coreRoot.path,
        pubGetRunner: countingPubGet(exitCode: 1),
        childRunner: successChild(),
        onHelperCacheEvent: cacheEvents.add,
      );
      expect(failed, isA<MoldCastSessionLaunchFailure>());
      expect((failed as MoldCastSessionLaunchFailure).kind, 'resolve');
      expect(cacheEvents, ['miss', 'resolve-failed']);
      expect(pubGetCount, 1);

      final entries = cacheRoot.listSync().whereType<Directory>().toList();
      expect(entries, hasLength(1));
      expect(
        File(
          p.join(entries.single.path, moldCastSessionHelperCacheStampFileName),
        ).existsSync(),
        isFalse,
      );

      cacheEvents.clear();
      final recovered = await launchBatchMoldCastSession(
        moldPath: moldDirectory.path,
        outputPath: outputDirectory.path,
        varsFlag: 'project_type=app,project_name=CacheDemo',
        force: true,
        helperCacheRoot: cacheRoot,
        foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
        foundryCoreOverridePath: coreRoot.path,
        pubGetRunner: countingPubGet(),
        childRunner: successChild(),
        onHelperCacheEvent: cacheEvents.add,
      );
      expect(recovered, isA<MoldCastSessionLaunchSuccess>());
      expect(pubGetCount, 2);
      expect(cacheEvents, ['miss']);
      expect(
        File(
          p.join(entries.single.path, moldCastSessionHelperCacheStampFileName),
        ).existsSync(),
        isTrue,
      );
    });

    test('writes a debug line when FOUNDRY_DEBUG_HELPER_CACHE is set',
        () async {
      await _writeLiveCallbackMold(moldDirectory);
      final cliRoot = await resolveFoundryCliRoot();
      final coreRoot = foundryCorePackageRoot();

      Future<MoldCastSessionLaunchResult> launchOnce({
        Map<String, String>? environment,
      }) {
        return launchBatchMoldCastSession(
          moldPath: moldDirectory.path,
          outputPath: outputDirectory.path,
          varsFlag: 'project_type=app,project_name=CacheDemo',
          force: true,
          helperCacheRoot: cacheRoot,
          foundryCliDependency: FoundryCliPathDependency(cliRoot.path),
          foundryCoreOverridePath: coreRoot.path,
          pubGetRunner: countingPubGet(),
          childRunner: successChild(),
          environment: environment,
          onHelperCacheEvent: cacheEvents.add,
        );
      }

      expect(await launchOnce(), isA<MoldCastSessionLaunchSuccess>());
      expect(cacheEvents, ['miss']);

      cacheEvents.clear();
      expect(
        await launchOnce(
          environment: const {'FOUNDRY_DEBUG_HELPER_CACHE': '1'},
        ),
        isA<MoldCastSessionLaunchSuccess>(),
      );
      expect(cacheEvents, ['hit']);
      expect(pubGetCount, 1);
    });
  });

  group('resolveFoundryCliHelperDependency', () {
    test('uses a path dep in this workspace', () async {
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

    test('uses a hosted dep when the package root is inside pub-cache',
        () async {
      final cliRoot = await resolveFoundryCliRoot();
      final dependency = await resolveFoundryCliHelperDependency(
        environment: {'PUB_CACHE': cliRoot.path},
      );
      expect(
        dependency,
        const FoundryCliHostedDependency(foundryCliVersion),
      );
    });
  });

  group('resolvePackageRoot', () {
    test('throws when the package cannot be resolved', () async {
      await expectLater(
        resolvePackageRoot('foundry_missing_package_for_session_tests'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Could not resolve package:'),
          ),
        ),
      );
    });
  });

  group('isPathInsidePubCache', () {
    test('detects pub-cache roots from environment candidates', () {
      expect(
        isPathInsidePubCache(
          p.join('/cache', 'hosted', 'pkg'),
          environment: const {'PUB_CACHE': '/cache'},
        ),
        isTrue,
      );
      expect(
        isPathInsidePubCache(
          '/cache',
          environment: const {'PUB_CACHE': '/cache'},
        ),
        isTrue,
      );
      expect(
        isPathInsidePubCache(
          p.join('/home', '.pub-cache', 'pkg'),
          environment: const {'HOME': '/home'},
        ),
        isTrue,
      );
      expect(
        isPathInsidePubCache(
          p.join('/local', 'Pub', 'Cache', 'pkg'),
          environment: const {'LOCALAPPDATA': '/local'},
        ),
        isTrue,
      );
      expect(
        isPathInsidePubCache(
          '/tmp/outside',
          environment: const {
            'PUB_CACHE': '/cache',
            'HOME': '/home',
            'LOCALAPPDATA': '/local',
          },
        ),
        isFalse,
      );
    });
  });

  group('decodeMoldCastSessionLaunchResult', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'foundry_session_result_',
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    Future<File> writeResult(Object? value) async {
      final file = File(p.join(tempDirectory.path, 'result.json'));
      if (value is String) {
        await file.writeAsString(value);
      } else {
        await file.writeAsString(jsonEncode(value));
      }
      return file;
    }

    test('decodes a success payload', () async {
      final file = await writeResult(
        '{'
        '"ok":true,'
        '"artifactCount":2,'
        '"vars":{"name":"demo"},'
        '"writtenFiles":["a.txt",1,"b.txt"],'
        '"outputDirectory":"/tmp/out"'
        '}',
      );

      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      );
      expect(result, isA<MoldCastSessionLaunchSuccess>());
      final success = result as MoldCastSessionLaunchSuccess;
      expect(success.artifactCount, 2);
      expect(success.vars, {'name': 'demo'});
      expect(success.writtenFilePaths, ['a.txt', 'b.txt']);
      expect(success.outputDirectory, '/tmp/out');
      expect(success.exitCode, FoundryExitCode.success.code);
    });

    test('decodes a describe success payload', () async {
      final file = await writeResult({
        'ok': true,
        'describe': true,
        'variables': [
          {
            'key': 'project_name',
            'kind': 'string',
            'label': 'Project name',
            'help': 'UNIQUE_HELP_PROJECT_NAME',
          },
        ],
      });

      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      );
      expect(result, isA<MoldCastSessionDescribeSuccess>());
      final success = result as MoldCastSessionDescribeSuccess;
      expect(success.variables, hasLength(1));
      expect(success.variables.single.help, 'UNIQUE_HELP_PROJECT_NAME');
      expect(success.exitCode, FoundryExitCode.success.code);
    });

    test('rejects describe success payloads missing variables', () async {
      final file = await writeResult({
        'ok': true,
        'describe': true,
      });

      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(result.kind, 'internal');
      expect(result.message, contains('missing variables'));
      expect(result.exitCode, FoundryExitCode.internalError.code);
    });

    test('rejects describe success payloads with invalid variables', () async {
      final file = await writeResult({
        'ok': true,
        'describe': true,
        'variables': [
          {
            'key': 'project_name',
            'kind': 'string',
          },
        ],
      });

      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(result.kind, 'internal');
      expect(result.message, contains('Describe success payload was invalid'));
      expect(result.exitCode, FoundryExitCode.internalError.code);
    });

    test('keeps a non-zero success exit code from the child', () async {
      final file = await writeResult({
        'ok': true,
        'artifactCount': 0,
        'vars': <String, Object?>{},
        'writtenFiles': <String>[],
        'outputDirectory': '/tmp/out',
      });

      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 3,
      ) as MoldCastSessionLaunchSuccess;
      expect(result.exitCode, 3);
    });

    test('rejects invalid JSON', () async {
      final file = await writeResult('{');
      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(result.kind, 'internal');
      expect(result.message, contains('not valid JSON'));
    });

    test('rejects a non-object JSON root', () async {
      final file = await writeResult(['nope']);
      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(result.message, contains('JSON object'));
    });

    test('rejects success payloads with missing fields', () async {
      final file = await writeResult({'ok': true, 'artifactCount': 'x'});
      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(result.message, contains('missing required fields'));
    });

    test('decodes failure payloads and normalizes blank fields', () async {
      final detailed = await writeResult({
        'ok': false,
        'kind': 'hook',
        'message': 'boom',
      });
      final detailedResult = decodeMoldCastSessionLaunchResult(
        resultFile: detailed,
        fallbackExitCode: 9,
      ) as MoldCastSessionLaunchFailure;
      expect(detailedResult.kind, 'hook');
      expect(detailedResult.message, 'boom');
      expect(detailedResult.exitCode, 9);

      final blank = await writeResult({'ok': false, 'kind': '', 'message': ''});
      final blankResult = decodeMoldCastSessionLaunchResult(
        resultFile: blank,
        fallbackExitCode: 0,
      ) as MoldCastSessionLaunchFailure;
      expect(blankResult.kind, 'internal');
      expect(blankResult.message, 'Session failed without a message.');
      expect(blankResult.exitCode, FoundryExitCode.userError.code);
    });

    test('decodes cancel payloads from interactive gather', () async {
      final file = await writeResult({
        'ok': false,
        'kind': 'cancel',
        'message': 'Cast cancelled.',
      });
      final result = decodeMoldCastSessionLaunchResult(
        resultFile: file,
        fallbackExitCode: FoundryExitCode.userError.code,
      ) as MoldCastSessionLaunchFailure;
      expect(result.kind, 'cancel');
      expect(result.message, 'Cast cancelled.');
      expect(result.exitCode, FoundryExitCode.userError.code);
    });
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

Future<void> _writeDescribeMetadataMold(Directory directory) async {
  final corePath = foundryCorePackageRoot().absolute.path;
  await File(p.join(directory.path, 'pubspec.yaml')).writeAsString('''
name: describe_metadata_mold
description: Mold with copyable metadata for describe-session tests
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: $corePath
''');

  await File(p.join(directory.path, 'variables.dart')).writeAsString(r'''
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(
      label: 'Project name',
      description: 'UNIQUE_DESC_PROJECT_NAME',
      help: 'UNIQUE_HELP_PROJECT_NAME',
      placeholder: 'UNIQUE_PLACEHOLDER',
    ),
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: {'app', 'package'},
      displayLabel: (value) => 'LABEL_$value',
    ),
  },
);
''');

  await Directory(p.join(directory.path, 'template')).create();
}
