import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/fixture_paths.dart';
import 'helpers/run_foundry.dart';

void main() {
  group('foundry mold import local', () {
    late Directory workDir;
    late String sourcePath;

    setUp(() async {
      workDir =
          await Directory.systemTemp.createTemp('foundry_cli_import_e2e_');
      sourcePath = fixturePath('import_source_mold');
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'copies a local mold to ./<name>/ under the working directory',
      () async {
        final result = await runFoundry(
          ['mold', 'import', 'local', '--path=$sourcePath'],
          workingDirectory: workDir.path,
        );

        expect(result.exitCode, 0, reason: result.stderr);

        final destination = Directory(p.join(workDir.path, 'greeter'));
        expect(destination.existsSync(), isTrue);
        expect(
          File(p.join(destination.path, 'pubspec.yaml')).readAsStringSync(),
          contains('name: greeter'),
        );
        expect(
          File(p.join(destination.path, 'template', 'README.md'))
              .readAsStringSync(),
          contains('greeter'),
        );
        expect(result.stdout, contains(destination.path));
      },
      tags: const ['e2e'],
    );
  });
}
