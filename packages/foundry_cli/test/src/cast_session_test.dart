import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart' show UsageException;
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
        expect(success.isSuccess, isTrue);
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
      expect(result.isSuccess, isFalse);
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

    test('skips all hook phases when every phase is in skipHooks', () async {
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
        skipHooks: MoldHookPhase.values.toSet(),
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(prepareCalled, isFalse);
      expect(
        await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
        'name=Ada\n',
      );
    });

    test('skips only the listed hook phase', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.preparePath);
      await touchHook(MoldHooks.shapePath);
      await touchHook(MoldHooks.finishPath);
      final called = <MoldHookPhase>[];

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
          prepare: (_) => called.add(MoldHookPhase.prepare),
          shape: (_) => called.add(MoldHookPhase.shape),
          finish: (_) => called.add(MoldHookPhase.finish),
        ),
      ).runBatch(
        varsFlag: 'project_name=Ada',
        skipHooks: {MoldHookPhase.shape},
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(called, [MoldHookPhase.prepare, MoldHookPhase.finish]);
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
      expect(result.isSuccess, isFalse);
      final failure = result as BatchCastSessionRenderFailure;
      expect(failure.message, isNotEmpty);
      expect(failure.message, failure.exception.message);
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

  group('CastSession.runInteractive', () {
    test(
      'honors live visibleWhen / defaultValue via gather values',
      () async {
        await writeTemplateFile(
          'out.txt',
          'type={{ project_type }}\n'
              'package={{ package_name }}\n',
        );

        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_type':
                  const FoundryStringVariable(label: 'Project type'),
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
        ).runInteractive(
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async =>
              {'project_type': 'package'},
        );

        expect(success, isA<BatchCastSessionSuccess>());
        final result = success as BatchCastSessionSuccess;
        expect(result.vars['project_type'], 'package');
        expect(result.vars['package_name'], 'demo_package');
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'type=package\npackage=demo_package\n',
        );
      },
    );

    test('returns cancelled when gather returns null', () async {
      await writeTemplateFile('out.txt', 'ok\n');
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
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async =>
            null,
      );

      expect(result, isA<BatchCastSessionCancelled>());
      expect(result.isSuccess, isFalse);
      expect(prepareCalled, isTrue);
      expect(
        File(p.join(outputDirectory.path, 'out.txt')).existsSync(),
        isFalse,
      );
    });

    test('returns hook failure when prepare throws', () async {
      await writeTemplateFile('out.txt', 'ok\n');
      await touchHook(MoldHooks.preparePath);
      var gatherCalled = false;

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
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          gatherCalled = true;
          return {'project_name': 'Ada'};
        },
      );

      expect(result, isA<BatchCastSessionHookFailure>());
      expect(gatherCalled, isFalse);
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.prepare);
      expect(failure.message, contains('prepare boom'));
    });

    test('returns gather failure when gather throws UsageException', () async {
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
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          throw UsageException(
            'FOUNDRY_E2E_VARS must be valid JSON: FormatException',
            '',
          );
        },
      );

      expect(result, isA<BatchCastSessionGatherFailure>());
      expect(result.isSuccess, isFalse);
      final failure = result as BatchCastSessionGatherFailure;
      expect(failure.message, contains('FOUNDRY_E2E_VARS'));
    });

    test('passes prepare seedValues into gather', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.preparePath);
      Map<String, Object?>? seenSeed;

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
            context.set('from_prepare', 'yes');
          },
        ),
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          seenSeed = Map<String, Object?>.of(seedValues);
          return {'project_name': 'Ada'};
        },
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(seenSeed, isNotNull);
      expect(seenSeed!['from_prepare'], 'yes');
    });

    test('skips prepare seeding when prepare is in skipHooks', () async {
      await writeTemplateFile('out.txt', 'name={{ project_name }}\n');
      await touchHook(MoldHooks.preparePath);
      Map<String, Object?>? seenSeed;
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
      ).runInteractive(
        skipHooks: {MoldHookPhase.prepare},
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async {
          seenSeed = Map<String, Object?>.of(seedValues);
          return {'project_name': 'Ada'};
        },
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(prepareCalled, isFalse);
      expect(seenSeed, isNotNull);
      expect(seenSeed!.containsKey('from_prepare'), isFalse);
    });

    test('returns context failure for wrong-typed gathered values', () async {
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
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async =>
            {'project_name': 42},
      );

      expect(result, isA<BatchCastSessionContextFailure>());
      final failure = result as BatchCastSessionContextFailure;
      expect(failure.message, contains('project_name'));
    });

    test('returns validation failure when validators reject values', () async {
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
          groupValidators: [
            (context) => context.optionalString('project_name') == 'bad'
                ? 'group validation failed at cast time'
                : null,
          ],
        ),
      );

      final result = await CastSession(
        mold: mold,
        outputPath: outputDirectory.path,
      ).runInteractive(
        gatherVariables: ({
          required variableGroup,
          required moldName,
          required moldDescription,
          seedValues = const {},
        }) async =>
            {'project_name': 'bad'},
      );

      expect(result, isA<BatchCastSessionValidationFailure>());
      final failure = result as BatchCastSessionValidationFailure;
      expect(failure.message, contains('Cast variables are invalid:'));
      expect(failure.message, contains('Name is reserved'));
      expect(failure.message, contains('group validation failed at cast time'));
    });

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
        ).runInteractive(
          gatherVariables: ({
            required variableGroup,
            required moldName,
            required moldDescription,
            seedValues = const {},
          }) async =>
              {},
        );

        expect(result, isA<BatchCastSessionSuccess>());
        final success = result as BatchCastSessionSuccess;
        expect(prepareContext, isNotNull);
        expect(shapeContext, same(prepareContext));
        expect(finishContext, same(prepareContext));
        expect(success.vars['project_name'], 'from-seeded-default');
        expect(success.vars['from_prepare'], 'yes');
        expect(success.vars['from_shape'], 'shaped');
        expect(
          await File(
            p.join(outputDirectory.path, 'finish_marker.txt'),
          ).readAsString(),
          'done',
        );
      },
    );
  });

  group('CastSession.runSeeded', () {
    test(
      'keeps non-variable prepare seeds and re-renders from seeded vars',
      () async {
        await writeTemplateFile(
          'out.txt',
          'name={{ project_name }}\n'
              'seed={{ seed }}\n'
              'shaped={{ shaped }}\n',
        );
        await touchHook(MoldHooks.preparePath);
        await touchHook(MoldHooks.shapePath);

        final result = await CastSession(
          mold: buildMold(
            variableGroup: const FoundryVariableGroup(
              variables: {
                'project_name': FoundryStringVariable(label: 'Project name'),
              },
            ),
          ),
          outputPath: outputDirectory.path,
          hooks: CastSessionHooks(
            prepare: (context) async {
              context.set('seed', 'from-prepare');
            },
            shape: (context) async {
              context.set('shaped', 'yes');
            },
          ),
        ).runSeeded(
          values: const {
            'project_name': 'Ada',
            'seed': 'stale-seed',
            'shaped': 'stale-shaped',
          },
          force: true,
        );

        expect(result, isA<BatchCastSessionSuccess>());
        final success = result as BatchCastSessionSuccess;
        expect(success.vars['project_name'], 'Ada');
        expect(success.vars['seed'], 'from-prepare');
        expect(success.vars['shaped'], 'yes');
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'name=Ada\n'
          'seed=from-prepare\n'
          'shaped=yes\n',
        );
      },
    );

    test('returns validation failure for invalid seeded variable values',
        () async {
      await writeTemplateFile('out.txt', '{{ project_name }}');
      final result = await CastSession(
        mold: buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(
                label: 'Project name',
                validators: [
                  (value, _) => value == 'bad' ? 'nope' : null,
                ],
              ),
            },
          ),
        ),
        outputPath: outputDirectory.path,
      ).runSeeded(values: const {'project_name': 'bad'});

      expect(result, isA<BatchCastSessionValidationFailure>());
      final failure = result as BatchCastSessionValidationFailure;
      expect(failure.message, contains('project_name: nope'));
    });

    test(
      'preserves explicit null from seeded values over defaultValue',
      () async {
        await writeTemplateFile(
          'out.txt',
          'name={{ project_name }}\n'
              'note={{ optional_note }}\n',
        );

        final result = await CastSession(
          mold: buildMold(
            variableGroup: FoundryVariableGroup(
              variables: {
                'project_name': const FoundryStringVariable(
                  label: 'Project name',
                ),
                'optional_note': FoundryStringVariable(
                  label: 'Optional note',
                  defaultValue: (_) => 'DEFAULT_NOTE',
                ),
              },
            ),
          ),
          outputPath: outputDirectory.path,
        ).runSeeded(
          values: const {
            'project_name': 'Ada',
            'optional_note': null,
          },
          force: true,
        );

        expect(result, isA<BatchCastSessionSuccess>());
        final success = result as BatchCastSessionSuccess;
        expect(success.vars['project_name'], 'Ada');
        expect(success.vars.containsKey('optional_note'), isTrue);
        expect(success.vars['optional_note'], isNull);
        expect(
          await File(p.join(outputDirectory.path, 'out.txt')).readAsString(),
          'name=Ada\n'
          'note=\n',
        );
      },
    );

    test('returns hook failure when prepare throws', () async {
      await writeTemplateFile('out.txt', 'ok\n');
      await touchHook(MoldHooks.preparePath);

      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        ),
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          prepare: (_) {
            throw const FoundryHookException('prepare boom');
          },
        ),
      ).runSeeded(values: const {'project_name': 'Ada'});

      expect(result, isA<BatchCastSessionHookFailure>());
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.prepare);
      expect(failure.message, contains('prepare boom'));
    });

    test(
      'returns context failure when seeded values include a wrong-typed '
      'variable',
      () async {
        await writeTemplateFile('out.txt', 'ok\n');

        final result = await CastSession(
          mold: buildMold(
            variableGroup: const FoundryVariableGroup(
              variables: {
                'project_name': FoundryStringVariable(label: 'Project name'),
              },
            ),
          ),
          outputPath: outputDirectory.path,
        ).runSeeded(values: const {'project_name': 42});

        expect(result, isA<BatchCastSessionContextFailure>());
        final failure = result as BatchCastSessionContextFailure;
        expect(failure.message, contains('project_name'));
      },
    );
  });

  group('CastSession.runFinishOnly', () {
    test('runs finish in-process without re-rendering templates', () async {
      await writeTemplateFile('README.md', '# {{ project_name }}\n');
      await touchHook(MoldHooks.finishPath);
      final stale = File(p.join(outputDirectory.path, 'README.md'));
      await stale.writeAsString('# stale template output\n');

      final beforeCwd = Directory.current.path;
      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        ),
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          finish: (context) async {
            context.set('finish_saw', context.requiredString('project_name'));
            // Relative path → proves cwd was the output directory.
            await File('finish_marker.txt').writeAsString('done');
          },
        ),
      ).runFinishOnly(vars: {'project_name': 'Ada'});

      expect(result, isA<BatchCastSessionSuccess>());
      final success = result as BatchCastSessionSuccess;
      expect(success.artifactCount, 0);
      expect(success.writtenFiles, isEmpty);
      expect(success.vars['project_name'], 'Ada');
      expect(success.vars['finish_saw'], 'Ada');
      expect(Directory.current.path, beforeCwd);
      expect(await stale.readAsString(), '# stale template output\n');
      expect(
        await File(
          p.join(outputDirectory.path, 'finish_marker.txt'),
        ).readAsString(),
        'done',
      );
    });

    test('returns missing-finish failure when hook file is absent', () async {
      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(variables: {}),
        ),
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          finish: (_) async {},
        ),
      ).runFinishOnly(vars: const {});

      expect(result, isA<BatchCastSessionMissingFinishHookFailure>());
      final failure = result as BatchCastSessionMissingFinishHookFailure;
      expect(failure.moldName, 'cast_session_demo');
      expect(failure.message, contains(MoldHooks.finishPath));
    });

    test('returns output-missing failure when output directory is gone',
        () async {
      final missingPath = p.join(outputDirectory.path, 'does_not_exist');
      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(variables: {}),
        ),
        outputPath: missingPath,
      ).runFinishOnly(vars: const {});

      expect(result, isA<BatchCastSessionOutputMissingFailure>());
      final failure = result as BatchCastSessionOutputMissingFailure;
      expect(failure.outputPath, missingPath);
      expect(failure.message, contains('does not exist'));
    });

    test('skips finish when finish is in skipHooks', () async {
      await touchHook(MoldHooks.finishPath);
      var finishCalled = false;
      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(variables: {}),
        ),
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          finish: (_) async {
            finishCalled = true;
          },
        ),
      ).runFinishOnly(
        vars: {'project_name': 'Ada'},
        skipHooks: {MoldHookPhase.finish},
      );

      expect(result, isA<BatchCastSessionSuccess>());
      expect(finishCalled, isFalse);
      expect(
        File(p.join(outputDirectory.path, 'finish_marker.txt')).existsSync(),
        isFalse,
      );
    });

    test(
      'skips finish without requiring the hook file when finish is skipped',
      () async {
        var finishCalled = false;
        final result = await CastSession(
          mold: buildMold(
            variableGroup: const FoundryVariableGroup(variables: {}),
          ),
          outputPath: outputDirectory.path,
          hooks: CastSessionHooks(
            finish: (_) async {
              finishCalled = true;
            },
          ),
        ).runFinishOnly(
          vars: const {},
          skipHooks: {MoldHookPhase.finish},
        );

        expect(result, isA<BatchCastSessionSuccess>());
        expect(finishCalled, isFalse);
      },
    );

    test('returns hook failure when finish throws', () async {
      await touchHook(MoldHooks.finishPath);
      final result = await CastSession(
        mold: buildMold(
          variableGroup: const FoundryVariableGroup(variables: {}),
        ),
        outputPath: outputDirectory.path,
        hooks: CastSessionHooks(
          finish: (_) {
            throw const FoundryHookException('finish boom');
          },
        ),
      ).runFinishOnly(vars: const {});

      expect(result, isA<BatchCastSessionHookFailure>());
      final failure = result as BatchCastSessionHookFailure;
      expect(failure.exception.phase, MoldHookPhase.finish);
      expect(failure.message, contains('finish boom'));
    });
  });
}
