import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';

Future<Mold> _loadCastPipelineMold(String moldPath) async {
  final directory = Directory(moldPath);
  final pubGet = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: directory.path,
  );
  expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}${pubGet.stderr}');

  final pubspecFile = File(p.join(directory.path, 'pubspec.yaml'));
  final pubspec = parseMoldPubspec(
    yamlContent: await pubspecFile.readAsString(),
    sourcePath: pubspecFile.path,
  );

  return Mold(
    directory: directory.absolute,
    pubspec: pubspec,
    variableGroup: const FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(label: 'Project name'),
      },
    ),
  );
}

void main() {
  group('cast pipeline', () {
    late Directory outputDirectory;
    late String moldPath;
    late Directory expectedDirectory;

    setUp(() async {
      outputDirectory =
          await Directory.systemTemp.createTemp('foundry_cast_e2e_');
      moldPath = fixturePath('cast_pipeline_mold');
      expectedDirectory = Directory(fixturePath('cast_pipeline/expected'));
    });

    tearDown(() async {
      if (outputDirectory.existsSync()) {
        await outputDirectory.delete(recursive: true);
      }
    });

    test(
      'casts a fixture mold through hooks and renders the expected tree',
      () async {
        final mold = await _loadCastPipelineMold(moldPath);

        final outcome = await castMold(
          mold: mold,
          outputPath: outputDirectory.path,
          values: const {'project_name': 'my project'},
        );

        expect(outcome.artifactCount, 2);
        expect(outcome.values['seed'], 'from-prepare');
        expect(outcome.values['shaped_value'], 'from-shape');
        expect(
          File(p.join(outputDirectory.path, 'cast_complete.txt')).existsSync(),
          isTrue,
        );
        expectDirectoryTreesMatch(
          expected: expectedDirectory,
          actual: outputDirectory,
        );
      },
      tags: const ['e2e'],
    );

    test(
      'runs all three hook phases in lifecycle order',
      () async {
        final mold = await _loadCastPipelineMold(moldPath);

        final outcome = await castMold(
          mold: mold,
          outputPath: outputDirectory.path,
          values: const {'project_name': 'hook order'},
        );

        expect(outcome.values['seed'], 'from-prepare');
        expect(outcome.values['shaped_value'], 'from-shape');
        expect(
          File(p.join(outputDirectory.path, 'cast_complete.txt')).existsSync(),
          isTrue,
        );
      },
      tags: const ['e2e'],
    );
  });
}
