import 'dart:convert';
import 'dart:io';

import 'package:foundry_cli/src/cast_session.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _PrepareSeed {
  const _PrepareSeed(this.label);
  final String label;
}

void main() {
  late Directory moldDirectory;
  late Directory outputDirectory;

  setUp(() async {
    moldDirectory = await Directory.systemTemp.createTemp(
      'foundry_cast_session_mold_',
    );
    outputDirectory = await Directory.systemTemp.createTemp(
      'foundry_cast_session_output_',
    );
  });

  tearDown(() async {
    if (moldDirectory.existsSync()) {
      await moldDirectory.delete(recursive: true);
    }
    if (outputDirectory.existsSync()) {
      await outputDirectory.delete(recursive: true);
    }
  });

  Mold buildMold({required FoundryVariableGroup variableGroup}) {
    return Mold(
      directory: moldDirectory,
      pubspec: const MoldPubspec(
        name: 'cast_session_demo',
        description: 'Mold used to exercise batch cast sessions',
        version: '0.0.1',
      ),
      variableGroup: variableGroup,
    );
  }

  Future<void> writeTemplateFile(String relativePath, String contents) async {
    final file = File(p.join(moldDirectory.path, 'template', relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<File> touchHook(String relativePath) async {
    final file = File(p.join(moldDirectory.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '// Placeholder so the session sees an on-disk hook file.\n',
    );
    return file;
  }

  group('CastSession.runBatch', () {
    test(
      'honors live visibleWhen, defaultValue, and validators',
      () async {
        await writeTemplateFile(
          'out.txt',
          'type={{ project_type }}\n'
              'package={{ package_name }}\n',
        );

        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_type': FoundryStringVariable(
                label: 'Project type',
                validators: [
                  (value, _) {
                    if (value != 'package' && value != 'app') {
                      return 'Must be package or app';
                    }
                    return null;
                  },
                ],
              ),
              'package_name': FoundryStringVariable(
                label: 'Package name',
                visibleWhen: (context) =>
                    context.optionalString('project_type') == 'package',
                defaultValue: (context) {
                  final type = context.optionalString('project_type');
                  return type == 'package' ? 'demo_package' : 'unused';
                },
              ),
            },
          ),
        );

        final success = await CastSession(
          mold: mold,
          outputPath: outputDirectory.path,
        ).runBatch(varsFlag: 'project_type=package');

        expect(success, isA<BatchCastSessionSuccess>());
        final result = success as BatchCastSessionSuccess;
        expect(result.artifactCount, 1);
        expect(result.vars['project_type'], 'package');
        expect(result.vars['package_name'], 'demo_package');
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'type=package\npackage=demo_package\n',
        );

        final hidden = await CastSession(
          mold: mold,
          outputPath: Directory.systemTemp
              .createTempSync('foundry_cast_session_hidden_')
              .path,
        ).runBatch(varsFlag: 'project_type=app');

        expect(hidden, isA<BatchCastSessionSuccess>());
        final hiddenResult = hidden as BatchCastSessionSuccess;
        expect(hiddenResult.vars['project_type'], 'app');
        expect(hiddenResult.vars.containsKey('package_name'), isFalse);
        await Directory(hiddenResult.outputDirectory.path)
            .delete(recursive: true);
      },
    );

    test(
      'forwards dirtyKeys so explicit JSON null beats defaultValue',
      () async {
        await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(
                label: 'Project name',
                defaultValue: (_) => 'from-default',
              ),
            },
          ),
        );

        final result = await CastSession(
          mold: mold,
          outputPath: outputDirectory.path,
        ).runBatch(
          varsFileValues: const {'project_name': null},
        );

        expect(result, isA<BatchCastSessionSuccess>());
        final success = result as BatchCastSessionSuccess;
        expect(success.vars['project_name'], isNull);
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'name=\n',
        );
      },
    );

    test(
      'runs prepare, shape, and finish in-process on one context instance',
      () async {
        await writeTemplateFile(
          'out.txt',
          'name={{ project_name }}\nshaped={{ from_shape }}\n',
        );
        await touchHook(MoldHooks.preparePath);
        await touchHook(MoldHooks.shapePath);
        await touchHook(MoldHooks.finishPath);

        FoundryContext? prepareContext;
        FoundryContext? shapeContext;
        FoundryContext? finishContext;
        const seed = _PrepareSeed('prepare-seed');

        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(
                label: 'Project name',
                defaultValue: (context) {
                  final prepareSeed = context.optional<_PrepareSeed>(
                    '_prepare_seed',
                  );
                  expect(prepareSeed, same(seed));
                  return 'from-seeded-default';
                },
              ),
            },
          ),
        );

        final result = await CastSession(
          mold: mold,
          outputPath: outputDirectory.path,
          hooks: CastSessionHooks(
            prepare: (context) {
              prepareContext = context
                ..set('_prepare_seed', seed)
                ..set('from_prepare', 'yes');
            },
            shape: (context) {
              shapeContext = context;
              expect(
                context.optional<_PrepareSeed>('_prepare_seed'),
                same(seed),
              );
              context.set('from_shape', 'shaped');
            },
            finish: (context) async {
              finishContext = context;
              expect(
                context.optional<_PrepareSeed>('_prepare_seed'),
                same(seed),
              );
              await File(
                p.join(context.outputDirectory.path, 'finish_marker.txt'),
              ).writeAsString('done');
            },
          ),
        ).runBatch();

        expect(result, isA<BatchCastSessionSuccess>());
        final success = result as BatchCastSessionSuccess;
        expect(prepareContext, isNotNull);
        expect(shapeContext, same(prepareContext));
        expect(finishContext, same(prepareContext));
        expect(success.vars['project_name'], 'from-seeded-default');
        expect(success.vars['from_prepare'], 'yes');
        expect(success.vars['from_shape'], 'shaped');
        expect(success.vars.containsKey('_prepare_seed'), isFalse);
        expect(() => jsonEncode(success.vars), returnsNormally);
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'name=from-seeded-default\nshaped=shaped\n',
        );
        expect(
          await File(
            p.join(outputDirectory.path, 'finish_marker.txt'),
          ).readAsString(),
          'done',
        );
      },
    );

    test('returns parse failure for unknown batch keys', () async {
      await writeTemplateFile('out.txt', 'ok\n');
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
      ).runBatch(varsFlag: 'unknown_key=value');

      expect(result, isA<BatchCastSessionParseFailure>());
      final failure = result as BatchCastSessionParseFailure;
      expect(failure.message, contains('unknown_key'));
    });

    test('returns hook failure when prepare throws', () async {
      await writeTemplateFile('out.txt', 'ok\n');
      await touchHook(MoldHooks.preparePath);
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          prepare: (_) {
            throw const FoundryHookException('prepare boom');
          },
        ),
      ).runBatch(varsFlag: 'project_name=Ada');

      expect(result, isA<BatchCastSessionHookFailure>());
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.prepare);
      expect(failure.message, contains('prepare boom'));
    });

    test('returns hook failure when shape throws', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.shapePath);
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          shape: (_) {
            throw const FoundryHookException('shape boom');
          },
        ),
      ).runBatch(varsFlag: 'project_name=Ada');

      expect(result, isA<BatchCastSessionHookFailure>());
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.shape);
      expect(failure.message, contains('shape boom'));
    });

    test('returns hook failure when finish throws', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.finishPath);
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          finish: (_) {
            throw const FoundryHookException('finish boom');
          },
        ),
      ).runBatch(varsFlag: 'project_name=Ada');

      expect(result, isA<BatchCastSessionHookFailure>());
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.finish);
      expect(failure.message, contains('finish boom'));
      expect(
        await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
        'name=Ada\n',
      );
    });

    test(
      'returns context failure when prepare seeds a wrong-typed variable',
      () async {
        await writeTemplateFile('out.txt', 'ok\n');
        await touchHook(MoldHooks.preparePath);
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        final result = await CastSession(
          mold: mold,
          outputPath: outputDirectory.path,
          hooks: CastSessionHooks(
            prepare: (context) {
              context.set('project_name', 42);
            },
          ),
        ).runBatch();

        expect(result, isA<BatchCastSessionContextFailure>());
        final failure = result as BatchCastSessionContextFailure;
        expect(failure.message, contains('project_name'));
      },
    );

    test('returns parse failure when group validation fails', () async {
      await writeTemplateFile('out.txt', 'ok\n');
      final mold = buildMold(
        variableGroup: FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(
              label: 'Project name',
              validators: [
                (value, _) {
                  if (value == 'bad') {
                    return 'Name is reserved';
                  }
                  return null;
                },
              ],
            ),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
      ).runBatch(varsFlag: 'project_name=bad');

      expect(result, isA<BatchCastSessionParseFailure>());
      final failure = result as BatchCastSessionParseFailure;
      expect(failure.message, contains('Name is reserved'));
    });

    test('skips hooks when noHooks is true', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.preparePath);
      var prepareCalled = false;

      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          prepare: (_) {
            prepareCalled = true;
          },
        ),
      ).runBatch(
        varsFlag: 'project_name=Ada',
        noHooks: true,
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(prepareCalled, isFalse);
      expect(
        await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
        'name=Ada\n',
      );
    });

    test('returns render failure on output conflict without force', () async {
      await writeTemplateFile('README.md', '# {{ project_name }}\n');
      await File(p.join(outputDirectory.path, 'README.md'))
          .writeAsString('existing\n');

      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
      ).runBatch(varsFlag: 'project_name=Ada');

      expect(result, isA<BatchCastSessionRenderFailure>());
    });

    test('overwrites conflicting output files when force is true', () async {
      await writeTemplateFile('README.md', '# {{ project_name }}\n');
      await File(p.join(outputDirectory.path, 'README.md'))
          .writeAsString('existing\n');

      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
      ).runBatch(
        varsFlag: 'project_name=Ada',
        force: true,
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(
        await File(p.join(outputDirectory.path, 'README.md')).readAsString(),
        '# Ada\n',
      );
    });
  });
}
