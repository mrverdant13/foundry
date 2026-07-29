import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../mold/fixtures/hooks/preserve_seeded_object.dart'
    as preserve_seeded_object;
import '../mold/mold_test_support.dart';

void main() {
  late Directory moldDirectory;
  late Directory outputDirectory;

  setUpAll(() async {
    moldDirectory =
        await Directory.systemTemp.createTemp('foundry_cast_runner_mold_');
    await writeMoldPubspec(
      directory: moldDirectory,
      name: 'cast_runner_demo',
      description: 'Mold used to exercise the cast pipeline',
    );
    await ensureMoldDependencies(moldDirectory);
  });

  tearDownAll(() => moldDirectory.deleteSync(recursive: true));

  setUp(() async {
    outputDirectory =
        await Directory.systemTemp.createTemp('foundry_cast_runner_output_');
  });

  tearDown(() async {
    await outputDirectory.delete(recursive: true);
    final hooksDir = Directory(p.join(moldDirectory.path, MoldHooks.directory));
    if (hooksDir.existsSync()) await hooksDir.delete(recursive: true);
    final templateDir = Directory(p.join(moldDirectory.path, 'template'));
    if (templateDir.existsSync()) await templateDir.delete(recursive: true);
  });

  Mold buildMold({required FoundryVariableGroup variableGroup}) {
    return Mold(
      directory: moldDirectory,
      pubspec: const MoldPubspec(
        name: 'cast_runner_demo',
        description: 'Mold used to exercise the cast pipeline',
        version: '0.0.1',
      ),
      variableGroup: variableGroup,
    );
  }

  Future<void> writeHook(String relativePath, String source) async {
    final file = File(p.join(moldDirectory.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(source);
  }

  Future<void> writeTemplateFile(String relativePath, String contents) async {
    final file = File(p.join(moldDirectory.path, 'template', relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> touchHook(String relativePath) async {
    final file = File(p.join(moldDirectory.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '// Placeholder so the cast runner sees an on-disk hook file.\n',
    );
  }

  group('castMold', () {
    test(
      'casts a mold to a temp output directory with a gathered variable map',
      () async {
        await writeTemplateFile('README.md', '# {{ project_name }}\n');
        await writeTemplateFile(
          'CHANGELOG.md',
          'Changes for {{ project_name }}.\n',
        );
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        final outcome = await castMold(
          mold: mold,
          outputPath: outputDirectory.path,
          values: const {'project_name': 'Ada'},
        );

        expect(outcome.artifactCount, 2);
        expect(outcome.writtenFiles, hasLength(2));
        expect(outcome.mold, same(mold));
        expect(outcome.values['project_name'], 'Ada');
        expect(
          await File(
            p.join(outputDirectory.path, 'README.md'),
          ).readAsString(),
          '# Ada\n',
        );
        expect(
          await File(
            p.join(outputDirectory.path, 'CHANGELOG.md'),
          ).readAsString(),
          'Changes for Ada.\n',
        );
      },
    );

    test(
      'creates the output directory before running hooks when it does not '
      'already exist',
      () async {
        final parentDirectory =
            await Directory.systemTemp.createTemp('foundry_cast_runner_new_');
        addTearDown(() => parentDirectory.delete(recursive: true));
        final freshOutputDirectory =
            Directory(p.join(parentDirectory.path, 'nested', 'output'));
        expect(freshOutputDirectory.existsSync(), isFalse);

        await writeHook(MoldHooks.preparePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
        await writeTemplateFile('output.txt', '{{ project_name }}');
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        final outcome = await castMold(
          mold: mold,
          outputPath: freshOutputDirectory.path,
          values: const {'project_name': 'Ada'},
        );

        expect(freshOutputDirectory.existsSync(), isTrue);
        expect(outcome.values['seed'], 'from-prepare');
        expect(
          await File(
            p.join(freshOutputDirectory.path, 'output.txt'),
          ).readAsString(),
          'Ada',
        );
      },
    );

    test(
      'runs the prepare hook before variable resolution and the shape hook '
      'after',
      () async {
        await writeHook(MoldHooks.preparePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
        await writeHook(MoldHooks.shapePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('shaped_value', 'from-shape');
}
''');
        await writeTemplateFile(
          'output.txt',
          'prepared={{ prepared_value }} shaped={{ shaped_value }}',
        );
        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'prepared_value': FoundryStringVariable(
                label: 'Prepared value',
                // Reads a key only the prepare hook sets: resolving this
                // default without throwing proves prepare ran first.
                defaultValue: (context) => context.requiredString('seed'),
              ),
            },
          ),
        );

        final outcome = await castMold(
          mold: mold,
          outputPath: outputDirectory.path,
        );

        expect(outcome.values['prepared_value'], 'from-prepare');
        // `shaped_value` is not a declared variable — it only appears
        // because the shape hook set it after variables were resolved and
        // before the template rendered.
        expect(outcome.values['shaped_value'], 'from-shape');
        expect(
          await File(
            p.join(outputDirectory.path, 'output.txt'),
          ).readAsString(),
          'prepared=from-prepare shaped=from-shape',
        );
      },
    );

    test('skips all hook phases when noHooks is true', () async {
      await writeHook(MoldHooks.preparePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
      await writeHook(MoldHooks.shapePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('shaped_value', 'from-shape');
}
''');
      await writeTemplateFile(
        'output.txt',
        'prepared={{ prepared_value }} shaped={{ shaped_value }}',
      );
      final mold = buildMold(
        variableGroup: FoundryVariableGroup(
          variables: {
            'prepared_value': FoundryStringVariable(
              label: 'Prepared value',
              defaultValue: (context) =>
                  context.optionalString('seed') ?? 'fallback',
            ),
          },
        ),
      );

      final outcome = await castMold(
        mold: mold,
        outputPath: outputDirectory.path,
        noHooks: true,
      );

      expect(outcome.values['prepared_value'], 'fallback');
      expect(outcome.values.containsKey('shaped_value'), isFalse);
      expect(
        await File(p.join(outputDirectory.path, 'output.txt')).readAsString(),
        'prepared=fallback shaped=',
      );
    });

    test(
      'leaves partial artifacts on disk when a later phase fails '
      '(no rollback)',
      () async {
        await writeHook(MoldHooks.finishPath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  throw const FoundryHookException('finish always fails');
}
''');
        await writeTemplateFile('a.txt', 'A: {{ project_name }}');
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        await expectLater(
          castMold(
            mold: mold,
            outputPath: outputDirectory.path,
            values: const {'project_name': 'demo'},
          ),
          throwsA(
            isA<MoldHookException>()
                .having((e) => e.phase, 'phase', MoldHookPhase.finish),
          ),
        );

        expect(
          await File(p.join(outputDirectory.path, 'a.txt')).readAsString(),
          'A: demo',
        );
      },
    );

    test(
      'throws CastVariablesInvalidException and renders nothing when '
      'variables fail validation',
      () async {
        await writeTemplateFile('a.txt', 'A: {{ project_name }}');
        final mold = buildMold(
          variableGroup: FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(
                label: 'Project name',
                validators: [(value, context) => 'always invalid'],
              ),
            },
          ),
        );

        await expectLater(
          castMold(
            mold: mold,
            outputPath: outputDirectory.path,
            values: const {'project_name': 'Ada'},
          ),
          throwsA(
            isA<CastVariablesInvalidException>().having(
              (e) => e.validation.fieldErrors['project_name'],
              'fieldErrors',
              contains('always invalid'),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );
  });

  group('prepareCastContext and completeCast', () {
    test('prepareCastContext runs prepare and creates the output directory',
        () async {
      await writeHook(MoldHooks.preparePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final context = await prepareCastContext(
        mold: mold,
        outputPath: outputDirectory.path,
      );

      expect(outputDirectory.existsSync(), isTrue);
      expect(context.entries['seed'], 'from-prepare');
      expect(context.outputDirectory.path, outputDirectory.path);
    });

    test('completeCast skips prepare so it is not run twice', () async {
      final counterPath = p.join(outputDirectory.path, 'prepare_count.txt');
      await writeHook(MoldHooks.preparePath, r'''
import 'dart:io';
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  final file = File('${context.outputDirectory.path}/prepare_count.txt');
  final current = file.existsSync() ? int.parse(file.readAsStringSync()) : 0;
  file.writeAsStringSync('${current + 1}');
  context.set('seed', 'from-prepare');
}
''');
      await writeTemplateFile(
        'output.txt',
        'prepared={{ prepared_value }}',
      );
      final mold = buildMold(
        variableGroup: FoundryVariableGroup(
          variables: {
            'prepared_value': FoundryStringVariable(
              label: 'Prepared value',
              defaultValue: (context) => context.requiredString('seed'),
            ),
          },
        ),
      );

      final context = await prepareCastContext(
        mold: mold,
        outputPath: outputDirectory.path,
      );
      expect(File(counterPath).readAsStringSync(), '1');

      final outcome = await completeCast(mold: mold, context: context);

      expect(File(counterPath).readAsStringSync(), '1');
      expect(outcome.values['prepared_value'], 'from-prepare');
    });

    test('prepareCastContext skips prepare when noHooks is true', () async {
      await writeHook(MoldHooks.preparePath, '''
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
''');
      final mold = buildMold(
        variableGroup: const FoundryVariableGroup(
          variables: {
            'project_name': FoundryStringVariable(label: 'Project name'),
          },
        ),
      );

      final context = await prepareCastContext(
        mold: mold,
        outputPath: outputDirectory.path,
        noHooks: true,
      );

      expect(context.entries.containsKey('seed'), isFalse);
    });

    test(
      'completeCast accepts a hand-built context without prepareCastContext',
      () async {
        await writeTemplateFile('README.md', '# {{ project_name }}\n');
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );
        final context = FoundryContext(
          values: const {'project_name': 'Ada'},
          logger: Logger(),
          moldDirectory: moldDirectory,
          outputDirectory: outputDirectory,
        );

        final outcome = await completeCast(
          mold: mold,
          context: context,
          noHooks: true,
        );

        expect(outcome.values['project_name'], 'Ada');
        expect(
          await File(
            p.join(outputDirectory.path, 'README.md'),
          ).readAsString(),
          '# Ada\n',
        );
      },
    );

    test(
      'completeCast preserves a dirty null over defaultValue when dirtyKeys '
      'is set',
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

        final withoutDirtyKeys = await completeCast(
          mold: mold,
          context: FoundryContext(
            values: const {'project_name': null},
            logger: Logger(),
            moldDirectory: moldDirectory,
            outputDirectory: outputDirectory,
          ),
          force: true,
          noHooks: true,
        );
        expect(withoutDirtyKeys.values['project_name'], 'from-default');

        final withDirtyKeys = await completeCast(
          mold: mold,
          context: FoundryContext(
            values: const {'project_name': null},
            logger: Logger(),
            moldDirectory: moldDirectory,
            outputDirectory: outputDirectory,
          ),
          dirtyKeys: const {'project_name'},
          force: true,
          noHooks: true,
        );
        expect(withDirtyKeys.values['project_name'], isNull);
      },
    );
  });

  group('castMold with CastHooks (in-process)', () {
    test(
      'preserves non-JSON object identity across prepare, shape, and finish',
      () async {
        await touchHook(MoldHooks.preparePath);
        await touchHook(MoldHooks.shapePath);
        await touchHook(MoldHooks.finishPath);
        final token = preserve_seeded_object.createSeedToken();
        FoundryContext? prepareContext;
        FoundryContext? shapeContext;
        FoundryContext? finishContext;

        await writeTemplateFile('out.txt', 'ok\n');
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        final outcome = await castMold(
          mold: mold,
          outputPath: outputDirectory.path,
          values: const {'project_name': 'Ada'},
          hooks: CastHooks(
            prepare: (context) {
              prepareContext = context..set('seed', token);
            },
            shape: (context) async {
              shapeContext = context;
              expect(
                identical(context.required<Object>('seed'), token),
                isTrue,
              );
              await preserve_seeded_object.run(context);
            },
            finish: (context) {
              finishContext = context;
              expect(
                identical(context.required<Object>('seen'), token),
                isTrue,
              );
            },
          ),
        );

        expect(prepareContext, isNotNull);
        expect(shapeContext, same(prepareContext));
        expect(finishContext, same(prepareContext));
        expect(identical(outcome.values['seen'], token), isTrue);
        expect(
          outcome.values['seen_type'],
          token.runtimeType.toString(),
        );
      },
    );

    test(
      'prepareCastContext and completeCast share in-process hook context',
      () async {
        await touchHook(MoldHooks.preparePath);
        await touchHook(MoldHooks.shapePath);
        final token = preserve_seeded_object.createSeedToken();
        await writeTemplateFile('out.txt', '{{ project_name }}\n');
        final mold = buildMold(
          variableGroup: const FoundryVariableGroup(
            variables: {
              'project_name': FoundryStringVariable(label: 'Project name'),
            },
          ),
        );

        final context = await prepareCastContext(
          mold: mold,
          outputPath: outputDirectory.path,
          values: const {'project_name': 'Ada'},
          hooks: CastHooks(
            prepare: (context) {
              context.set('seed', token);
            },
          ),
        );
        expect(identical(context.required<Object>('seed'), token), isTrue);

        final outcome = await completeCast(
          mold: mold,
          context: context,
          hooks: const CastHooks(
            shape: preserve_seeded_object.run,
          ),
        );

        expect(identical(outcome.values['seen'], token), isTrue);
      },
    );
  });
}
