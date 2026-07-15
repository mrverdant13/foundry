import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/compare_directory_trees.dart';
import 'helpers/fixture_paths.dart';

void main() {
  group('cast pipeline', () {
    late Directory outputDirectory;
    late String moldPath;
    late Directory expectedDirectory;

    setUp(() async {
      moldPath = fixturePath('cast_pipeline_mold');
      expectedDirectory = Directory(fixturePath('cast_pipeline/expected'));
      outputDirectory =
          await Directory.systemTemp.createTemp('foundry_cast_e2e_');
    });

    tearDown(() async {
      if (outputDirectory.existsSync()) {
        await outputDirectory.delete(recursive: true);
      }
    });

    test(
      'casts a fixture mold through hooks and renders the expected tree',
      () async {
        final mold = await loadMold(moldPath);

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
        final mold = await loadMold(moldPath);

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
